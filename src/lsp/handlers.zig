//! LSP request/response handlers
//! Implements LSP-specific message handlers using the JSON-RPC client layer

const std = @import("std");
const Client = @import("client.zig").Client;
const InitializeParams = @import("client.zig").InitializeParams;
const InitializeResult = @import("client.zig").InitializeResult;
const ServerCapabilities = @import("client.zig").ServerCapabilities;

/// Initialize the LSP connection with a language server
/// This must be called before any other LSP operations
pub fn initialize(
    client: *Client,
    workspace_root: ?[]const u8,
) !InitializeResult {
    if (client.state != .uninitialized) {
        return error.AlreadyInitialized;
    }

    const params = InitializeParams{
        .process_id = std.os.linux.getpid(),
        .root_uri = workspace_root,
        .capabilities = .{
            .text_document = .{
                .synchronization = .{
                    .did_open = true,
                    .did_change = true,
                    .did_save = true,
                    .did_close = true,
                },
                .completion = .{ .dynamic_registration = false },
                .hover = .{ .dynamic_registration = false },
            },
            .workspace = .{
                .apply_edit = false,
                .workspace_edit = .{ .document_changes = false },
            },
        },
    };

    client.state = .initializing;
    const request = try client.initialize(params);
    _ = request;

    // TODO: Send actual request via sendRequest and parse response
    // For now, return dummy result
    return InitializeResult{
        .capabilities = .{},
    };
}

/// Send initialized notification after successful initialize
pub fn sendInitialized(client: *Client) !void {
    if (client.state != .initialized) {
        return error.NotInitialized;
    }

    const empty_params = .{};
    try client.sendNotification("initialized", empty_params);
}

/// Text document synchronization handlers
/// Send didOpen notification when a file is opened
pub fn didOpen(
    client: *Client,
    uri: []const u8,
    language_id: []const u8,
    version: u32,
    text: []const u8,
) !void {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{
            .uri = uri,
            .languageId = language_id,
            .version = version,
            .text = text,
        },
    };

    try client.sendNotification("textDocument/didOpen", params);
}

/// Send didChange notification when a file is modified
pub fn didChange(
    client: *Client,
    uri: []const u8,
    version: u32,
    content_changes: []const ContentChange,
) !void {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{
            .uri = uri,
            .version = version,
        },
        .contentChanges = content_changes,
    };

    try client.sendNotification("textDocument/didChange", params);
}

/// Send didSave notification when a file is saved
pub fn didSave(
    client: *Client,
    uri: []const u8,
    text: ?[]const u8,
) !void {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .text = text,
    };

    try client.sendNotification("textDocument/didSave", params);
}

/// Send didClose notification when a file is closed
pub fn didClose(client: *Client, uri: []const u8) !void {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
    };

    try client.sendNotification("textDocument/didClose", params);
}

/// Request completion at a given position
pub fn completion(
    client: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .position = .{
            .line = line,
            .character = character,
        },
    };

    return try client.sendRequest("textDocument/completion", params, callback, callback_ctx);
}

/// Request hover information at a given position
pub fn hover(
    client: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .position = .{
            .line = line,
            .character = character,
        },
    };

    return try client.sendRequest("textDocument/hover", params, callback, callback_ctx);
}

/// Request go-to-definition at a given position
pub fn definition(
    client: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .position = .{
            .line = line,
            .character = character,
        },
    };

    return try client.sendRequest("textDocument/definition", params, callback, callback_ctx);
}

/// Request references at a given position
pub fn references(
    client: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
    include_declaration: bool,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .position = .{
            .line = line,
            .character = character,
        },
        .context = .{
            .includeDeclaration = include_declaration,
        },
    };

    return try client.sendRequest("textDocument/references", params, callback, callback_ctx);
}

/// Request document formatting
pub fn formatting(
    client: *Client,
    uri: []const u8,
    tab_size: u32,
    insert_spaces: bool,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .options = .{
            .tabSize = tab_size,
            .insertSpaces = insert_spaces,
        },
    };

    return try client.sendRequest("textDocument/formatting", params, callback, callback_ctx);
}

/// Request code actions at a given position
pub fn codeAction(
    client: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
    diagnostics: []const Diagnostic,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .range = .{
            .start = .{
                .line = line,
                .character = character,
            },
            .end = .{
                .line = line,
                .character = character,
            },
        },
        .context = .{
            .diagnostics = diagnostics,
        },
    };

    return try client.sendRequest("textDocument/codeAction", params, callback, callback_ctx);
}

// Re-export Diagnostic type for convenience
pub const Diagnostic = @import("response_parser.zig").Diagnostic;

/// Request document symbols (outline)
pub fn documentSymbol(
    client: *Client,
    uri: []const u8,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
    };

    return try client.sendRequest("textDocument/documentSymbol", params, callback, callback_ctx);
}

/// Request signature help at cursor position (Stream B)
pub fn signatureHelp(
    client: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .position = .{
            .line = line,
            .character = character,
        },
    };

    return try client.sendRequest("textDocument/signatureHelp", params, callback, callback_ctx);
}

/// Prepare rename (check if rename is valid at position) (Stream A)
pub fn prepareRename(
    client: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .position = .{
            .line = line,
            .character = character,
        },
    };

    return try client.sendRequest("textDocument/prepareRename", params, callback, callback_ctx);
}

/// Request rename with new name (Stream A)
pub fn rename(
    client: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
    new_name: []const u8,
    callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
    callback_ctx: ?*anyopaque,
) !u32 {
    if (!client.isReady()) {
        return error.NotInitialized;
    }

    const params = .{
        .textDocument = .{ .uri = uri },
        .position = .{
            .line = line,
            .character = character,
        },
        .newName = new_name,
    };

    return try client.sendRequest("textDocument/rename", params, callback, callback_ctx);
}

/// Content change for didChange notification
pub const ContentChange = struct {
    text: []const u8,
};

// === Tests ===

test "handlers: initialize requires uninitialized state" {
    const allocator = std.testing.allocator;
    var client = Client.init(allocator, null);
    defer client.deinit();

    // First initialize should work
    _ = try initialize(&client, null);

    // Second initialize should fail
    try std.testing.expectError(error.AlreadyInitialized, initialize(&client, null));
}

test "handlers: operations require initialized state" {
    const allocator = std.testing.allocator;
    var client = Client.init(allocator, null);
    defer client.deinit();

    // Operations should fail before initialization
    try std.testing.expectError(error.NotInitialized, didOpen(&client, "file:///test.zig", "zig", 0, "content"));
    try std.testing.expectError(error.NotInitialized, didClose(&client, "file:///test.zig"));
}
