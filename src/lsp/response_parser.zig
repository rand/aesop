//! LSP response parser
//! Parses LSP JSON responses into typed structures

const std = @import("std");
const Completion = @import("../editor/completion.zig");
const CompletionItem = Completion.CompletionItem;
const CompletionKind = Completion.CompletionKind;

/// Parse LSP completion response and extract items
pub fn parseCompletionResponse(allocator: std.mem.Allocator, json_text: []const u8) ![]CompletionItem {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Response can be either CompletionList or array of CompletionItem
    // CompletionList: { "isIncomplete": bool, "items": [...] }
    // CompletionItem[]: [...]

    var items_array: std.json.Value = undefined;

    if (root == .object) {
        // CompletionList format
        items_array = root.object.get("items") orelse return error.MissingItems;
    } else if (root == .array) {
        // Direct array format
        items_array = root;
    } else {
        return error.InvalidCompletionResponse;
    }

    if (items_array != .array) {
        return error.ItemsNotArray;
    }

    var result = std.ArrayList(CompletionItem).empty;
    errdefer {
        for (result.items) |*item| {
            item.deinit(allocator);
        }
        result.deinit(allocator);
    }

    for (items_array.array.items) |item_value| {
        if (item_value != .object) continue;
        const item_obj = item_value.object;

        // Extract label (required)
        const label_value = item_obj.get("label") orelse continue;
        if (label_value != .string) continue;
        const label = try allocator.dupe(u8, label_value.string);

        // Extract kind (optional, default to text)
        var kind: CompletionKind = .text;
        if (item_obj.get("kind")) |kind_value| {
            if (kind_value == .integer) {
                kind = @enumFromInt(@as(u8, @intCast(kind_value.integer)));
            }
        }

        // Extract detail (optional)
        var detail: ?[]const u8 = null;
        if (item_obj.get("detail")) |detail_value| {
            if (detail_value == .string) {
                detail = try allocator.dupe(u8, detail_value.string);
            }
        }

        // Extract documentation (optional)
        var documentation: ?[]const u8 = null;
        if (item_obj.get("documentation")) |doc_value| {
            if (doc_value == .string) {
                documentation = try allocator.dupe(u8, doc_value.string);
            } else if (doc_value == .object) {
                // MarkupContent format: { "kind": "markdown", "value": "..." }
                if (doc_value.object.get("value")) |value| {
                    if (value == .string) {
                        documentation = try allocator.dupe(u8, value.string);
                    }
                }
            }
        }

        // Extract insertText (optional, defaults to label)
        var insert_text: ?[]const u8 = null;
        if (item_obj.get("insertText")) |insert_value| {
            if (insert_value == .string) {
                insert_text = try allocator.dupe(u8, insert_value.string);
            }
        }

        // Extract sortText (optional)
        var sort_text: ?[]const u8 = null;
        if (item_obj.get("sortText")) |sort_value| {
            if (sort_value == .string) {
                sort_text = try allocator.dupe(u8, sort_value.string);
            }
        }

        const completion_item = CompletionItem{
            .label = label,
            .kind = kind,
            .detail = detail,
            .documentation = documentation,
            .insert_text = insert_text,
            .sort_text = sort_text,
        };

        try result.append(allocator, completion_item);
    }

    return result.toOwnedSlice(allocator);
}

/// Parse hover response and extract markdown content
pub fn parseHoverResponse(allocator: std.mem.Allocator, json_text: []const u8) ![]const u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidHoverResponse;

    // Hover response: { "contents": MarkupContent | MarkedString | MarkedString[] | string }
    const contents = root.object.get("contents") orelse return error.MissingContents;

    if (contents == .string) {
        return try allocator.dupe(u8, contents.string);
    } else if (contents == .object) {
        // MarkupContent: { "kind": "markdown", "value": "..." }
        if (contents.object.get("value")) |value| {
            if (value == .string) {
                return try allocator.dupe(u8, value.string);
            }
        }
    } else if (contents == .array) {
        // Array of MarkedString - concatenate
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(allocator);

        for (contents.array.items) |item| {
            if (item == .string) {
                try buf.appendSlice(allocator, item.string);
                try buf.append(allocator, '\n');
            } else if (item == .object) {
                if (item.object.get("value")) |value| {
                    if (value == .string) {
                        try buf.appendSlice(allocator, value.string);
                        try buf.append(allocator, '\n');
                    }
                }
            }
        }

        return buf.toOwnedSlice(allocator);
    }

    return error.InvalidContentsFormat;
}

// === Tests ===

test "parse completion response: CompletionList format" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "isIncomplete": false,
        \\  "items": [
        \\    {
        \\      "label": "println",
        \\      "kind": 3,
        \\      "detail": "fn(fmt: []const u8) void",
        \\      "insertText": "println"
        \\    },
        \\    {
        \\      "label": "print",
        \\      "kind": 3,
        \\      "detail": "fn(fmt: []const u8) void"
        \\    }
        \\  ]
        \\}
    ;

    const items = try parseCompletionResponse(allocator, json);
    defer {
        for (items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(items);
    }

    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expectEqualStrings("println", items[0].label);
    try std.testing.expectEqual(CompletionKind.function, items[0].kind);
    try std.testing.expectEqualStrings("fn(fmt: []const u8) void", items[0].detail.?);
}

test "parse completion response: array format" {
    const allocator = std.testing.allocator;

    const json =
        \\[
        \\  {
        \\    "label": "variable",
        \\    "kind": 6
        \\  }
        \\]
    ;

    const items = try parseCompletionResponse(allocator, json);
    defer {
        for (items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(items);
    }

    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("variable", items[0].label);
    try std.testing.expectEqual(CompletionKind.variable, items[0].kind);
}

test "parse hover response: markdown format" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "contents": {
        \\    "kind": "markdown",
        \\    "value": "# Function\n\nDoes something cool"
        \\  }
        \\}
    ;

    const text = try parseHoverResponse(allocator, json);
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "Function") != null);
}
