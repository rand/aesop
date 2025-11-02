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

/// Diagnostic severity levels (LSP spec)
pub const DiagnosticSeverity = enum(u8) {
    @"error" = 1,
    warning = 2,
    information = 3,
    hint = 4,

    pub fn fromInt(value: i64) DiagnosticSeverity {
        return switch (value) {
            1 => .@"error",
            2 => .warning,
            3 => .information,
            4 => .hint,
            else => .hint,
        };
    }
};

/// Position in a document (LSP spec)
pub const Position = struct {
    line: u32,
    character: u32,
};

/// Range in a document (LSP spec)
pub const Range = struct {
    start: Position,
    end: Position,
};

/// Diagnostic item from LSP
pub const Diagnostic = struct {
    range: Range,
    severity: DiagnosticSeverity,
    code: ?[]const u8, // Allocated, must free
    source: ?[]const u8, // Allocated, must free
    message: []const u8, // Allocated, must free

    pub fn deinit(self: *Diagnostic, allocator: std.mem.Allocator) void {
        if (self.code) |code| allocator.free(code);
        if (self.source) |source| allocator.free(source);
        allocator.free(self.message);
    }
};

/// Parse publishDiagnostics notification and extract diagnostics
pub fn parseDiagnosticsNotification(allocator: std.mem.Allocator, json_text: []const u8) !struct {
    uri: []const u8, // Allocated
    diagnostics: []Diagnostic, // Allocated
} {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidDiagnosticNotification;

    // Extract URI
    const uri_value = root.object.get("uri") orelse return error.MissingUri;
    if (uri_value != .string) return error.InvalidUri;
    const uri = try allocator.dupe(u8, uri_value.string);
    errdefer allocator.free(uri);

    // Extract diagnostics array
    const diagnostics_value = root.object.get("diagnostics") orelse return error.MissingDiagnostics;
    if (diagnostics_value != .array) return error.DiagnosticsNotArray;

    var diagnostics = std.ArrayList(Diagnostic).empty;
    errdefer {
        for (diagnostics.items) |*diag| {
            diag.deinit(allocator);
        }
        diagnostics.deinit(allocator);
    }

    for (diagnostics_value.array.items) |diag_value| {
        if (diag_value != .object) continue;
        const diag_obj = diag_value.object;

        // Parse range (required)
        const range_value = diag_obj.get("range") orelse continue;
        if (range_value != .object) continue;
        const range_obj = range_value.object;

        const start_value = range_obj.get("start") orelse continue;
        const end_value = range_obj.get("end") orelse continue;
        if (start_value != .object or end_value != .object) continue;

        const start_line = if (start_value.object.get("line")) |v| blk: {
            if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else continue;
        } else continue;
        const start_char = if (start_value.object.get("character")) |v| blk: {
            if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else continue;
        } else continue;

        const end_line = if (end_value.object.get("line")) |v| blk: {
            if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else continue;
        } else continue;
        const end_char = if (end_value.object.get("character")) |v| blk: {
            if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else continue;
        } else continue;

        const range = Range{
            .start = .{ .line = start_line, .character = start_char },
            .end = .{ .line = end_line, .character = end_char },
        };

        // Parse severity (optional, default to hint)
        var severity: DiagnosticSeverity = .hint;
        if (diag_obj.get("severity")) |sev_value| {
            if (sev_value == .integer) {
                severity = DiagnosticSeverity.fromInt(sev_value.integer);
            }
        }

        // Parse message (required)
        const message_value = diag_obj.get("message") orelse continue;
        if (message_value != .string) continue;
        const message = try allocator.dupe(u8, message_value.string);

        // Parse code (optional)
        var code: ?[]const u8 = null;
        if (diag_obj.get("code")) |code_value| {
            if (code_value == .string) {
                code = try allocator.dupe(u8, code_value.string);
            } else if (code_value == .integer) {
                // Some servers send integer codes
                var buf: [32]u8 = undefined;
                const code_str = try std.fmt.bufPrint(&buf, "{d}", .{code_value.integer});
                code = try allocator.dupe(u8, code_str);
            }
        }

        // Parse source (optional)
        var source: ?[]const u8 = null;
        if (diag_obj.get("source")) |source_value| {
            if (source_value == .string) {
                source = try allocator.dupe(u8, source_value.string);
            }
        }

        const diagnostic = Diagnostic{
            .range = range,
            .severity = severity,
            .code = code,
            .source = source,
            .message = message,
        };

        try diagnostics.append(allocator, diagnostic);
    }

    return .{
        .uri = uri,
        .diagnostics = try diagnostics.toOwnedSlice(allocator),
    };
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

test "parse diagnostics notification: error and warning" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "uri": "file:///test.zig",
        \\  "diagnostics": [
        \\    {
        \\      "range": {
        \\        "start": {"line": 5, "character": 10},
        \\        "end": {"line": 5, "character": 15}
        \\      },
        \\      "severity": 1,
        \\      "code": "E001",
        \\      "source": "zls",
        \\      "message": "undefined variable 'foo'"
        \\    },
        \\    {
        \\      "range": {
        \\        "start": {"line": 10, "character": 0},
        \\        "end": {"line": 10, "character": 5}
        \\      },
        \\      "severity": 2,
        \\      "message": "unused variable 'bar'"
        \\    }
        \\  ]
        \\}
    ;

    const result = try parseDiagnosticsNotification(allocator, json);
    defer {
        allocator.free(result.uri);
        for (result.diagnostics) |*diag| {
            diag.deinit(allocator);
        }
        allocator.free(result.diagnostics);
    }

    try std.testing.expectEqualStrings("file:///test.zig", result.uri);
    try std.testing.expectEqual(@as(usize, 2), result.diagnostics.len);

    // Check first diagnostic (error)
    try std.testing.expectEqual(DiagnosticSeverity.@"error", result.diagnostics[0].severity);
    try std.testing.expectEqual(@as(u32, 5), result.diagnostics[0].range.start.line);
    try std.testing.expectEqualStrings("undefined variable 'foo'", result.diagnostics[0].message);
    try std.testing.expectEqualStrings("E001", result.diagnostics[0].code.?);
    try std.testing.expectEqualStrings("zls", result.diagnostics[0].source.?);

    // Check second diagnostic (warning)
    try std.testing.expectEqual(DiagnosticSeverity.warning, result.diagnostics[1].severity);
    try std.testing.expectEqual(@as(u32, 10), result.diagnostics[1].range.start.line);
    try std.testing.expectEqualStrings("unused variable 'bar'", result.diagnostics[1].message);
}

test "parse diagnostics notification: empty diagnostics" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "uri": "file:///test.zig",
        \\  "diagnostics": []
        \\}
    ;

    const result = try parseDiagnosticsNotification(allocator, json);
    defer {
        allocator.free(result.uri);
        allocator.free(result.diagnostics);
    }

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}

test "parse completion response: edge case - missing optional fields" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "items": [
        \\    {
        \\      "label": "minimal"
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

    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("minimal", items[0].label);
    try std.testing.expectEqual(CompletionKind.text, items[0].kind); // Default
    try std.testing.expectEqual(@as(?[]const u8, null), items[0].detail);
}

test "parse hover response: string format" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "contents": "Simple string hover"
        \\}
    ;

    const text = try parseHoverResponse(allocator, json);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("Simple string hover", text);
}

test "parse hover response: array format" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "contents": [
        \\    "Line 1",
        \\    "Line 2",
        \\    {"value": "Line 3"}
        \\  ]
        \\}
    ;

    const text = try parseHoverResponse(allocator, json);
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "Line 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Line 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Line 3") != null);
}
