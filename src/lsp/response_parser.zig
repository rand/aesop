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

/// Location from LSP - represents a position in a file
pub const Location = struct {
    uri: []const u8, // Allocated, must free
    range: Range,

    pub fn deinit(self: *Location, allocator: std.mem.Allocator) void {
        allocator.free(self.uri);
    }
};

/// Parse goto definition response and extract location(s)
/// Returns array of locations (can be empty if no definition found)
pub fn parseDefinitionResponse(allocator: std.mem.Allocator, json_text: []const u8) ![]Location {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Definition response can be:
    // - null (no definition)
    // - Location (single)
    // - Location[] (array)
    // - LocationLink[] (more complex, treat as Location for now)

    if (root == .null) {
        // No definition found
        return try allocator.alloc(Location, 0);
    }

    var locations = std.ArrayList(Location).empty;
    errdefer {
        for (locations.items) |*loc| {
            loc.deinit(allocator);
        }
        locations.deinit(allocator);
    }

    if (root == .object) {
        // Single Location
        const loc = try parseLocation(allocator, root);
        try locations.append(allocator, loc);
    } else if (root == .array) {
        // Array of Location or LocationLink
        for (root.array.items) |item| {
            if (item != .object) continue;
            const loc = parseLocation(allocator, item) catch continue;
            try locations.append(allocator, loc);
        }
    } else {
        return error.InvalidDefinitionResponse;
    }

    return locations.toOwnedSlice(allocator);
}

/// Parse references response and extract locations
/// Returns array of locations (can be empty if no references found)
pub fn parseReferencesResponse(allocator: std.mem.Allocator, json_text: []const u8) ![]Location {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // References response is always an array of Location, or null
    if (root == .null) {
        return try allocator.alloc(Location, 0);
    }

    if (root != .array) {
        return error.InvalidReferencesResponse;
    }

    var locations = std.ArrayList(Location).empty;
    errdefer {
        for (locations.items) |*loc| {
            loc.deinit(allocator);
        }
        locations.deinit(allocator);
    }

    for (root.array.items) |item| {
        if (item != .object) continue;
        const loc = parseLocation(allocator, item) catch continue;
        try locations.append(allocator, loc);
    }

    return locations.toOwnedSlice(allocator);
}

/// TextEdit from LSP - represents a text replacement
pub const TextEdit = struct {
    range: Range,
    newText: []const u8, // Allocated, must free

    pub fn deinit(self: *TextEdit, allocator: std.mem.Allocator) void {
        allocator.free(self.newText);
    }
};

/// Parse formatting response and extract text edits
/// Returns array of text edits (can be empty)
pub fn parseFormattingResponse(allocator: std.mem.Allocator, json_text: []const u8) ![]TextEdit {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Formatting response is always an array of TextEdit, or null
    if (root == .null) {
        return try allocator.alloc(TextEdit, 0);
    }

    if (root != .array) {
        return error.InvalidFormattingResponse;
    }

    var edits = std.ArrayList(TextEdit).empty;
    errdefer {
        for (edits.items) |*edit| {
            edit.deinit(allocator);
        }
        edits.deinit(allocator);
    }

    for (root.array.items) |item| {
        if (item != .object) continue;
        const edit = parseTextEdit(allocator, item) catch continue;
        try edits.append(allocator, edit);
    }

    return edits.toOwnedSlice(allocator);
}

/// Parse a single TextEdit from JSON
fn parseTextEdit(allocator: std.mem.Allocator, value: std.json.Value) !TextEdit {
    if (value != .object) return error.InvalidTextEdit;
    const obj = value.object;

    // Extract range
    const range_value = obj.get("range") orelse return error.MissingRange;
    if (range_value != .object) return error.InvalidRange;
    const range_obj = range_value.object;

    const start_value = range_obj.get("start") orelse return error.MissingStart;
    const end_value = range_obj.get("end") orelse return error.MissingEnd;
    if (start_value != .object or end_value != .object) return error.InvalidPosition;

    const start_line = if (start_value.object.get("line")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidLine;
    } else return error.MissingLine;

    const start_char = if (start_value.object.get("character")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidCharacter;
    } else return error.MissingCharacter;

    const end_line = if (end_value.object.get("line")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidLine;
    } else return error.MissingLine;

    const end_char = if (end_value.object.get("character")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidCharacter;
    } else return error.MissingCharacter;

    const range = Range{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = end_line, .character = end_char },
    };

    // Extract newText
    const new_text_value = obj.get("newText") orelse return error.MissingNewText;
    if (new_text_value != .string) return error.InvalidNewText;
    const new_text = try allocator.dupe(u8, new_text_value.string);

    return TextEdit{
        .range = range,
        .newText = new_text,
    };
}

/// Parse a single Location from JSON
fn parseLocation(allocator: std.mem.Allocator, value: std.json.Value) !Location {
    if (value != .object) return error.InvalidLocation;
    const obj = value.object;

    // Extract URI
    const uri_value = obj.get("uri") orelse return error.MissingUri;
    if (uri_value != .string) return error.InvalidUri;
    const uri = try allocator.dupe(u8, uri_value.string);
    errdefer allocator.free(uri);

    // Extract range
    const range_value = obj.get("range") orelse return error.MissingRange;
    if (range_value != .object) return error.InvalidRange;
    const range_obj = range_value.object;

    const start_value = range_obj.get("start") orelse return error.MissingStart;
    const end_value = range_obj.get("end") orelse return error.MissingEnd;
    if (start_value != .object or end_value != .object) return error.InvalidPosition;

    const start_line = if (start_value.object.get("line")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidLine;
    } else return error.MissingLine;

    const start_char = if (start_value.object.get("character")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidCharacter;
    } else return error.MissingCharacter;

    const end_line = if (end_value.object.get("line")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidLine;
    } else return error.MissingLine;

    const end_char = if (end_value.object.get("character")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidCharacter;
    } else return error.MissingCharacter;

    const range = Range{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = end_line, .character = end_char },
    };

    return Location{
        .uri = uri,
        .range = range,
    };
}

/// Code action from LSP - represents a quick fix or refactoring
pub const CodeAction = struct {
    title: []const u8, // Display name
    kind: ?[]const u8, // e.g., "quickfix", "refactor"
    edit: ?WorkspaceEdit, // Changes to apply
    command: ?Command, // Command to execute

    pub fn deinit(self: *CodeAction, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        if (self.kind) |k| allocator.free(k);
        if (self.edit) |*e| e.deinit(allocator);
        if (self.command) |*c| c.deinit(allocator);
    }
};

/// LSP Command
pub const Command = struct {
    title: []const u8,
    command: []const u8,
    // arguments: ?[]std.json.Value, // TODO: Parse if needed

    pub fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.command);
    }
};

/// Workspace edit (simplified - only document changes for now)
pub const WorkspaceEdit = struct {
    // For simplicity, we'll just track that an edit exists
    // Full implementation would parse document changes
    has_changes: bool,

    pub fn deinit(self: *WorkspaceEdit, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Parse code action response and extract actions
pub fn parseCodeActionResponse(allocator: std.mem.Allocator, json_text: []const u8) ![]CodeAction {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Response is either null or array of CodeAction/Command
    if (root == .null) {
        return try allocator.alloc(CodeAction, 0);
    }

    if (root != .array) {
        return error.InvalidCodeActionResponse;
    }

    var actions = std.ArrayList(CodeAction).empty;
    errdefer {
        for (actions.items) |*action| {
            action.deinit(allocator);
        }
        actions.deinit(allocator);
    }

    for (root.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        // Check if it's a Command (has "command" field) or CodeAction (has "title" field)
        const title_value = obj.get("title") orelse continue;
        if (title_value != .string) continue;
        const title = try allocator.dupe(u8, title_value.string);
        errdefer allocator.free(title);

        // Extract kind (optional)
        var kind: ?[]const u8 = null;
        if (obj.get("kind")) |kind_value| {
            if (kind_value == .string) {
                kind = try allocator.dupe(u8, kind_value.string);
            }
        }
        errdefer if (kind) |k| allocator.free(k);

        // Extract edit (optional, simplified)
        var edit: ?WorkspaceEdit = null;
        if (obj.get("edit")) |_| {
            edit = WorkspaceEdit{ .has_changes = true };
        }

        // Extract command (optional)
        var command: ?Command = null;
        if (obj.get("command")) |cmd_value| {
            if (cmd_value == .object) {
                const cmd_obj = cmd_value.object;
                if (cmd_obj.get("title")) |cmd_title| {
                    if (cmd_title == .string) {
                        if (cmd_obj.get("command")) |cmd_cmd| {
                            if (cmd_cmd == .string) {
                                command = Command{
                                    .title = try allocator.dupe(u8, cmd_title.string),
                                    .command = try allocator.dupe(u8, cmd_cmd.string),
                                };
                            }
                        }
                    }
                }
            }
        }

        try actions.append(allocator, CodeAction{
            .title = title,
            .kind = kind,
            .edit = edit,
            .command = command,
        });
    }

    return actions.toOwnedSlice(allocator);
}

/// Symbol kind from LSP
pub const SymbolKind = enum(u8) {
    file = 1,
    module = 2,
    namespace = 3,
    package = 4,
    class = 5,
    method = 6,
    property = 7,
    field = 8,
    constructor = 9,
    @"enum" = 10,
    interface = 11,
    function = 12,
    variable = 13,
    constant = 14,
    string = 15,
    number = 16,
    boolean = 17,
    array = 18,
    object = 19,
    key = 20,
    null = 21,
    enum_member = 22,
    @"struct" = 23,
    event = 24,
    operator = 25,
    type_parameter = 26,
};

/// Document symbol from LSP (hierarchical)
pub const DocumentSymbol = struct {
    name: []const u8,
    detail: ?[]const u8,
    kind: SymbolKind,
    range: Range, // Full range including leading/trailing whitespace
    selection_range: Range, // Range of the symbol's identifier
    children: []DocumentSymbol, // Nested symbols (e.g., methods in class)

    pub fn deinit(self: *DocumentSymbol, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.detail) |d| allocator.free(d);
        // Recursively free children
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }
};

/// Parse document symbol response and extract symbols
pub fn parseDocumentSymbolResponse(allocator: std.mem.Allocator, json_text: []const u8) ![]DocumentSymbol {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Response is either null or array of DocumentSymbol
    if (root == .null) {
        return try allocator.alloc(DocumentSymbol, 0);
    }

    if (root != .array) {
        return error.InvalidDocumentSymbolResponse;
    }

    var symbols = std.ArrayList(DocumentSymbol).empty;
    errdefer {
        for (symbols.items) |*symbol| {
            symbol.deinit(allocator);
        }
        symbols.deinit(allocator);
    }

    for (root.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        // Extract name (required)
        const name_value = obj.get("name") orelse continue;
        if (name_value != .string) continue;
        const name = try allocator.dupe(u8, name_value.string);
        errdefer allocator.free(name);

        // Extract kind (required)
        const kind_value = obj.get("kind") orelse {
            allocator.free(name);
            continue;
        };
        if (kind_value != .integer) {
            allocator.free(name);
            continue;
        }
        const kind: SymbolKind = @enumFromInt(@as(u8, @intCast(kind_value.integer)));

        // Extract detail (optional)
        var detail: ?[]const u8 = null;
        if (obj.get("detail")) |detail_value| {
            if (detail_value == .string) {
                detail = try allocator.dupe(u8, detail_value.string);
            }
        }
        errdefer if (detail) |d| allocator.free(d);

        // Extract range (required)
        const range = parseRange(obj.get("range") orelse {
            allocator.free(name);
            if (detail) |d| allocator.free(d);
            continue;
        }) catch {
            allocator.free(name);
            if (detail) |d| allocator.free(d);
            continue;
        };

        // Extract selectionRange (required)
        const selection_range = parseRange(obj.get("selectionRange") orelse {
            allocator.free(name);
            if (detail) |d| allocator.free(d);
            continue;
        }) catch {
            allocator.free(name);
            if (detail) |d| allocator.free(d);
            continue;
        };

        // Parse children (optional, recursive)
        var children = std.ArrayList(DocumentSymbol).empty;
        if (obj.get("children")) |children_value| {
            if (children_value == .array) {
                for (children_value.array.items) |child_item| {
                    if (parseDocumentSymbolFromJson(allocator, child_item)) |child| {
                        try children.append(allocator, child);
                    } else |_| {
                        // Skip malformed children
                        continue;
                    }
                }
            }
        }
        const children_slice = try children.toOwnedSlice(allocator);
        errdefer {
            for (children_slice) |*child| {
                child.deinit(allocator);
            }
            allocator.free(children_slice);
        }

        try symbols.append(allocator, DocumentSymbol{
            .name = name,
            .detail = detail,
            .kind = kind,
            .range = range,
            .selection_range = selection_range,
            .children = children_slice,
        });
    }

    return symbols.toOwnedSlice(allocator);
}

/// Parse a single document symbol from JSON (helper for recursive parsing)
fn parseDocumentSymbolFromJson(allocator: std.mem.Allocator, item: std.json.Value) !DocumentSymbol {
    if (item != .object) return error.InvalidSymbol;
    const obj = item.object;

    // Extract name (required)
    const name_value = obj.get("name") orelse return error.MissingName;
    if (name_value != .string) return error.InvalidName;
    const name = try allocator.dupe(u8, name_value.string);
    errdefer allocator.free(name);

    // Extract kind (required)
    const kind_value = obj.get("kind") orelse return error.MissingKind;
    if (kind_value != .integer) return error.InvalidKind;
    const kind: SymbolKind = @enumFromInt(@as(u8, @intCast(kind_value.integer)));

    // Extract detail (optional)
    var detail: ?[]const u8 = null;
    if (obj.get("detail")) |detail_value| {
        if (detail_value == .string) {
            detail = try allocator.dupe(u8, detail_value.string);
        }
    }
    errdefer if (detail) |d| allocator.free(d);

    // Extract range (required)
    const range = try parseRange(obj.get("range") orelse return error.MissingRange);

    // Extract selectionRange (required)
    const selection_range = try parseRange(obj.get("selectionRange") orelse return error.MissingSelectionRange);

    // Parse children recursively (optional)
    var children = std.ArrayList(DocumentSymbol).empty;
    if (obj.get("children")) |children_value| {
        if (children_value == .array) {
            for (children_value.array.items) |child_item| {
                if (parseDocumentSymbolFromJson(allocator, child_item)) |child| {
                    try children.append(allocator, child);
                } else |_| {
                    continue;
                }
            }
        }
    }
    const children_slice = try children.toOwnedSlice(allocator);
    errdefer {
        for (children_slice) |*child| {
            child.deinit(allocator);
        }
        allocator.free(children_slice);
    }

    return DocumentSymbol{
        .name = name,
        .detail = detail,
        .kind = kind,
        .range = range,
        .selection_range = selection_range,
        .children = children_slice,
    };
}

/// Parse a Range from JSON value
fn parseRange(value: std.json.Value) !Range {
    if (value != .object) return error.InvalidRange;
    const range_obj = value.object;

    const start_value = range_obj.get("start") orelse return error.MissingStart;
    const end_value = range_obj.get("end") orelse return error.MissingEnd;
    if (start_value != .object or end_value != .object) return error.InvalidPosition;

    const start_line = if (start_value.object.get("line")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidLine;
    } else return error.MissingLine;

    const start_char = if (start_value.object.get("character")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidCharacter;
    } else return error.MissingCharacter;

    const end_line = if (end_value.object.get("line")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidLine;
    } else return error.MissingLine;

    const end_char = if (end_value.object.get("character")) |v| blk: {
        if (v == .integer) break :blk @as(u32, @intCast(v.integer)) else return error.InvalidCharacter;
    } else return error.MissingCharacter;

    return Range{
        .start = .{ .line = start_line, .character = start_char },
        .end = .{ .line = end_line, .character = end_char },
    };
}

/// Signature help structures (Stream B)
pub const ParameterInformation = struct {
    label: []const u8, // Parameter name or range
    documentation: ?[]const u8,

    pub fn deinit(self: *ParameterInformation, allocator: std.mem.Allocator) void {
        allocator.free(self.label);
        if (self.documentation) |doc| allocator.free(doc);
    }
};

pub const SignatureInformation = struct {
    label: []const u8, // Function signature
    documentation: ?[]const u8,
    parameters: []ParameterInformation,
    active_parameter: ?u32,

    pub fn deinit(self: *SignatureInformation, allocator: std.mem.Allocator) void {
        allocator.free(self.label);
        if (self.documentation) |doc| allocator.free(doc);
        for (self.parameters) |*param| {
            param.deinit(allocator);
        }
        allocator.free(self.parameters);
    }
};

pub const SignatureHelp = struct {
    signatures: []SignatureInformation,
    active_signature: ?u32,
    active_parameter: ?u32,

    pub fn deinit(self: *SignatureHelp, allocator: std.mem.Allocator) void {
        for (self.signatures) |*sig| {
            sig.deinit(allocator);
        }
        allocator.free(self.signatures);
    }
};

/// Parse signature help response
pub fn parseSignatureHelpResponse(allocator: std.mem.Allocator, json_text: []const u8) !SignatureHelp {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    if (root == .null) {
        return SignatureHelp{
            .signatures = try allocator.alloc(SignatureInformation, 0),
            .active_signature = null,
            .active_parameter = null,
        };
    }

    if (root != .object) return error.InvalidSignatureHelpResponse;
    const obj = root.object;

    // Parse signatures array
    const sigs_value = obj.get("signatures") orelse return error.MissingSignatures;
    if (sigs_value != .array) return error.InvalidSignatures;

    var signatures = std.ArrayList(SignatureInformation).empty;
    errdefer {
        for (signatures.items) |*sig| {
            sig.deinit(allocator);
        }
        signatures.deinit(allocator);
    }

    for (sigs_value.array.items) |sig_value| {
        if (sig_value != .object) continue;
        const sig_obj = sig_value.object;

        const label = sig_obj.get("label") orelse continue;
        if (label != .string) continue;
        const label_str = try allocator.dupe(u8, label.string);
        errdefer allocator.free(label_str);

        var documentation: ?[]const u8 = null;
        if (sig_obj.get("documentation")) |doc_value| {
            if (doc_value == .string) {
                documentation = try allocator.dupe(u8, doc_value.string);
            }
        }
        errdefer if (documentation) |doc| allocator.free(doc);

        // Parse parameters
        var parameters = std.ArrayList(ParameterInformation).empty;
        errdefer {
            for (parameters.items) |*param| {
                param.deinit(allocator);
            }
            parameters.deinit(allocator);
        }

        if (sig_obj.get("parameters")) |params_value| {
            if (params_value == .array) {
                for (params_value.array.items) |param_value| {
                    if (param_value != .object) continue;
                    const param_obj = param_value.object;

                    const param_label = param_obj.get("label") orelse continue;
                    if (param_label != .string) continue;
                    const param_label_str = try allocator.dupe(u8, param_label.string);

                    var param_doc: ?[]const u8 = null;
                    if (param_obj.get("documentation")) |param_doc_value| {
                        if (param_doc_value == .string) {
                            param_doc = try allocator.dupe(u8, param_doc_value.string);
                        }
                    }

                    try parameters.append(allocator, ParameterInformation{
                        .label = param_label_str,
                        .documentation = param_doc,
                    });
                }
            }
        }

        const active_param = if (sig_obj.get("activeParameter")) |ap| blk: {
            if (ap == .integer) break :blk @as(u32, @intCast(ap.integer)) else break :blk null;
        } else null;

        try signatures.append(allocator, SignatureInformation{
            .label = label_str,
            .documentation = documentation,
            .parameters = try parameters.toOwnedSlice(allocator),
            .active_parameter = active_param,
        });
    }

    const active_sig = if (obj.get("activeSignature")) |as| blk: {
        if (as == .integer) break :blk @as(u32, @intCast(as.integer)) else break :blk null;
    } else null;

    const active_param = if (obj.get("activeParameter")) |ap| blk: {
        if (ap == .integer) break :blk @as(u32, @intCast(ap.integer)) else break :blk null;
    } else null;

    return SignatureHelp{
        .signatures = try signatures.toOwnedSlice(allocator),
        .active_signature = active_sig,
        .active_parameter = active_param,
    };
}

/// Rename structures (Stream A)
pub const PrepareRenameResponse = struct {
    range: Range,
    placeholder: []const u8,

    pub fn deinit(self: *PrepareRenameResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.placeholder);
    }
};

pub const RenameEdit = struct {
    uri: []const u8,
    edits: []TextEdit,

    pub fn deinit(self: *RenameEdit, allocator: std.mem.Allocator) void {
        allocator.free(self.uri);
        for (self.edits) |*edit| {
            edit.deinit(allocator);
        }
        allocator.free(self.edits);
    }
};

/// Parse prepare rename response
pub fn parsePrepareRenameResponse(allocator: std.mem.Allocator, json_text: []const u8) !PrepareRenameResponse {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root == .null) return error.CannotRename;
    if (root != .object) return error.InvalidPrepareRenameResponse;

    const obj = root.object;
    const range = parseRange(obj.get("range") orelse return error.MissingRange) catch return error.InvalidRange;

    const placeholder_value = obj.get("placeholder") orelse return error.MissingPlaceholder;
    if (placeholder_value != .string) return error.InvalidPlaceholder;
    const placeholder = try allocator.dupe(u8, placeholder_value.string);

    return PrepareRenameResponse{
        .range = range,
        .placeholder = placeholder,
    };
}

/// Parse rename response (WorkspaceEdit with document changes)
pub fn parseRenameResponse(allocator: std.mem.Allocator, json_text: []const u8) ![]RenameEdit {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root == .null) {
        return try allocator.alloc(RenameEdit, 0);
    }

    if (root != .object) return error.InvalidRenameResponse;
    const obj = root.object;

    // Parse workspace edit
    const changes_value = obj.get("changes") orelse return error.MissingChanges;
    if (changes_value != .object) return error.InvalidChanges;

    var rename_edits = std.ArrayList(RenameEdit).empty;
    errdefer {
        for (rename_edits.items) |*edit| {
            edit.deinit(allocator);
        }
        rename_edits.deinit(allocator);
    }

    var changes_iter = changes_value.object.iterator();
    while (changes_iter.next()) |entry| {
        const uri = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(uri);

        if (entry.value_ptr.* != .array) {
            allocator.free(uri);
            continue;
        }

        var text_edits = std.ArrayList(TextEdit).empty;
        errdefer {
            for (text_edits.items) |*te| {
                te.deinit(allocator);
            }
            text_edits.deinit(allocator);
        }

        for (entry.value_ptr.array.items) |edit_value| {
            const edit = parseTextEdit(allocator, edit_value) catch continue;
            try text_edits.append(allocator, edit);
        }

        try rename_edits.append(allocator, RenameEdit{
            .uri = uri,
            .edits = try text_edits.toOwnedSlice(allocator),
        });
    }

    return rename_edits.toOwnedSlice(allocator);
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

test "parse definition response: single location" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "uri": "file:///src/main.zig",
        \\  "range": {
        \\    "start": {"line": 42, "character": 10},
        \\    "end": {"line": 42, "character": 20}
        \\  }
        \\}
    ;

    const locations = try parseDefinitionResponse(allocator, json);
    defer {
        for (locations) |*loc| {
            loc.deinit(allocator);
        }
        allocator.free(locations);
    }

    try std.testing.expectEqual(@as(usize, 1), locations.len);
    try std.testing.expectEqualStrings("file:///src/main.zig", locations[0].uri);
    try std.testing.expectEqual(@as(u32, 42), locations[0].range.start.line);
    try std.testing.expectEqual(@as(u32, 10), locations[0].range.start.character);
}

test "parse definition response: array of locations" {
    const allocator = std.testing.allocator;

    const json =
        \\[
        \\  {
        \\    "uri": "file:///src/foo.zig",
        \\    "range": {
        \\      "start": {"line": 10, "character": 5},
        \\      "end": {"line": 10, "character": 15}
        \\    }
        \\  },
        \\  {
        \\    "uri": "file:///src/bar.zig",
        \\    "range": {
        \\      "start": {"line": 20, "character": 8},
        \\      "end": {"line": 20, "character": 18}
        \\    }
        \\  }
        \\]
    ;

    const locations = try parseDefinitionResponse(allocator, json);
    defer {
        for (locations) |*loc| {
            loc.deinit(allocator);
        }
        allocator.free(locations);
    }

    try std.testing.expectEqual(@as(usize, 2), locations.len);
    try std.testing.expectEqualStrings("file:///src/foo.zig", locations[0].uri);
    try std.testing.expectEqual(@as(u32, 10), locations[0].range.start.line);
    try std.testing.expectEqualStrings("file:///src/bar.zig", locations[1].uri);
    try std.testing.expectEqual(@as(u32, 20), locations[1].range.start.line);
}

test "parse definition response: null (no definition)" {
    const allocator = std.testing.allocator;

    const json = "null";

    const locations = try parseDefinitionResponse(allocator, json);
    defer allocator.free(locations);

    try std.testing.expectEqual(@as(usize, 0), locations.len);
}

test "parse references response: array of locations" {
    const allocator = std.testing.allocator;

    const json =
        \\[
        \\  {
        \\    "uri": "file:///src/main.zig",
        \\    "range": {
        \\      "start": {"line": 10, "character": 5},
        \\      "end": {"line": 10, "character": 15}
        \\    }
        \\  },
        \\  {
        \\    "uri": "file:///src/utils.zig",
        \\    "range": {
        \\      "start": {"line": 25, "character": 8},
        \\      "end": {"line": 25, "character": 18}
        \\    }
        \\  }
        \\]
    ;

    const locations = try parseReferencesResponse(allocator, json);
    defer {
        for (locations) |*loc| {
            loc.deinit(allocator);
        }
        allocator.free(locations);
    }

    try std.testing.expectEqual(@as(usize, 2), locations.len);
    try std.testing.expectEqualStrings("file:///src/main.zig", locations[0].uri);
    try std.testing.expectEqual(@as(u32, 10), locations[0].range.start.line);
    try std.testing.expectEqualStrings("file:///src/utils.zig", locations[1].uri);
    try std.testing.expectEqual(@as(u32, 25), locations[1].range.start.line);
}

test "parse references response: null (no references)" {
    const allocator = std.testing.allocator;

    const json = "null";

    const locations = try parseReferencesResponse(allocator, json);
    defer allocator.free(locations);

    try std.testing.expectEqual(@as(usize, 0), locations.len);
}

test "parse formatting response: text edits" {
    const allocator = std.testing.allocator;

    const json =
        \\[
        \\  {
        \\    "range": {
        \\      "start": {"line": 5, "character": 0},
        \\      "end": {"line": 5, "character": 10}
        \\    },
        \\    "newText": "const foo = 42;"
        \\  },
        \\  {
        \\    "range": {
        \\      "start": {"line": 10, "character": 0},
        \\      "end": {"line": 10, "character": 0}
        \\    },
        \\    "newText": "\n"
        \\  }
        \\]
    ;

    const edits = try parseFormattingResponse(allocator, json);
    defer {
        for (edits) |*edit| {
            edit.deinit(allocator);
        }
        allocator.free(edits);
    }

    try std.testing.expectEqual(@as(usize, 2), edits.len);

    // First edit
    try std.testing.expectEqual(@as(u32, 5), edits[0].range.start.line);
    try std.testing.expectEqual(@as(u32, 0), edits[0].range.start.character);
    try std.testing.expectEqualStrings("const foo = 42;", edits[0].newText);

    // Second edit
    try std.testing.expectEqual(@as(u32, 10), edits[1].range.start.line);
    try std.testing.expectEqualStrings("\n", edits[1].newText);
}

test "parse formatting response: null (no edits)" {
    const allocator = std.testing.allocator;

    const json = "null";

    const edits = try parseFormattingResponse(allocator, json);
    defer allocator.free(edits);

    try std.testing.expectEqual(@as(usize, 0), edits.len);
}
