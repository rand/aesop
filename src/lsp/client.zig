//! LSP client implementation
//! Handles Language Server Protocol communication via JSON-RPC 2.0

const std = @import("std");
const zigjr = @import("zigjr");
const Process = @import("process.zig").Process;

/// LSP client state
pub const Client = struct {
    allocator: std.mem.Allocator,
    state: State,
    request_id: u32,
    pending_requests: std.AutoHashMap(u32, PendingRequest),
    process: ?Process,
    read_buffer: [65536]u8, // 64KB buffer for reading messages
    notification_handler: ?NotificationHandler, // Handler for server notifications
    notification_ctx: ?*anyopaque, // Context for notification handler

    pub const State = enum {
        uninitialized,
        initializing,
        initialized,
        shutdown,
        exited,
    };

    pub const PendingRequest = struct {
        method: []const u8,
        timestamp: i64,
        callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
        callback_ctx: ?*anyopaque, // User context passed to callback
    };

    /// Notification handler callback type
    pub const NotificationHandler = *const fn (ctx: ?*anyopaque, method: []const u8, params: []const u8) anyerror!void;

    /// Initialize LSP client with server process
    pub fn init(allocator: std.mem.Allocator, process: ?Process) Client {
        return .{
            .allocator = allocator,
            .state = .uninitialized,
            .request_id = 0,
            .pending_requests = std.AutoHashMap(u32, PendingRequest).init(allocator),
            .process = process,
            .read_buffer = undefined,
            .notification_handler = null,
            .notification_ctx = null,
        };
    }

    /// Set notification handler
    pub fn setNotificationHandler(self: *Client, handler: NotificationHandler, ctx: ?*anyopaque) void {
        self.notification_handler = handler;
        self.notification_ctx = ctx;
    }

    /// Clean up client
    pub fn deinit(self: *Client) void {
        var iter = self.pending_requests.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.method);
        }
        self.pending_requests.deinit();
    }

    /// Send initialize request
    pub fn initialize(self: *Client, params: InitializeParams) !InitializeRequest {
        if (self.state != .uninitialized) {
            return error.AlreadyInitialized;
        }

        self.state = .initializing;
        const id = self.nextRequestId();

        return InitializeRequest{
            .id = id,
            .params = params,
        };
    }

    /// Handle initialize response
    pub fn handleInitializeResponse(self: *Client, response: InitializeResult) !void {
        if (self.state != .initializing) {
            return error.InvalidState;
        }

        self.state = .initialized;
        _ = response;
    }

    /// Send initialized notification
    pub fn sendInitialized(self: *Client) !void {
        if (self.state != .initialized) {
            return error.NotInitialized;
        }
    }

    /// Send shutdown request
    pub fn shutdown(self: *Client) !u32 {
        if (self.state != .initialized) {
            return error.InvalidState;
        }

        self.state = .shutdown;
        return self.nextRequestId();
    }

    /// Send exit notification
    pub fn exit(self: *Client) !void {
        if (self.state != .shutdown) {
            return error.InvalidState;
        }

        self.state = .exited;
    }

    /// Get next request ID
    fn nextRequestId(self: *Client) u32 {
        const id = self.request_id;
        self.request_id +%= 1;
        return id;
    }

    /// Check if client is ready for requests
    pub fn isReady(self: *const Client) bool {
        return self.state == .initialized;
    }

    /// Send JSON-RPC request (returns immediately, callback invoked on response)
    pub fn sendRequest(
        self: *Client,
        method: []const u8,
        params: anytype,
        callback: *const fn (ctx: ?*anyopaque, result: []const u8) anyerror!void,
        callback_ctx: ?*anyopaque,
    ) !u32 {
        var process = &(self.process orelse return error.ProcessNotRunning);

        const id = self.nextRequestId();

        // Serialize request using zigjr
        const request_json = try zigjr.composer.makeRequestJson(
            self.allocator,
            method,
            params,
            zigjr.RpcId{ .num = @intCast(id) },
        );
        defer self.allocator.free(request_json);

        // Track request for response matching
        const method_copy = try self.allocator.dupe(u8, method);
        try self.pending_requests.put(id, .{
            .method = method_copy,
            .timestamp = std.time.milliTimestamp(),
            .callback = callback,
            .callback_ctx = callback_ctx,
        });

        // Send to server via process
        try process.writeMessage(request_json);

        return id;
    }

    /// Send JSON-RPC notification (no response expected)
    pub fn sendNotification(self: *Client, method: []const u8, params: anytype) !void {
        var process = &(self.process orelse return error.ProcessNotRunning);

        // Serialize notification using zigjr (notifications have no ID)
        const notification_json = try zigjr.composer.makeRequestJson(
            self.allocator,
            method,
            params,
            zigjr.RpcId{ .none = {} },
        );
        defer self.allocator.free(notification_json);

        // Send to server via process
        try process.writeMessage(notification_json);
    }

    /// Handle incoming message from server (response or notification)
    pub fn handleMessage(self: *Client, json: []const u8) !void {
        // Try to parse as JSON to detect if it's a notification or response
        // Notifications have "method" but no "id" (or id is null)
        // Responses have "id" and either "result" or "error"

        // Simple heuristic: check if JSON contains "method" field
        // If yes, it's a notification; otherwise it's a response
        const is_notification = std.mem.indexOf(u8, json, "\"method\"") != null;

        if (is_notification) {
            try self.handleNotification(json);
        } else {
            try self.handleResponse(json);
        }
    }

    /// Handle incoming response from server
    fn handleResponse(self: *Client, json: []const u8) !void {
        // Parse JSON-RPC response using zigjr
        var rpc_response = try zigjr.parseRpcResponse(self.allocator, json);
        defer rpc_response.deinit();

        // Extract ID
        const id: u32 = switch (rpc_response.id) {
            .num => |n| @intCast(n),
            .str => return error.InvalidResponseId,
            .none => return error.ResponseWithoutId, // This shouldn't happen for responses
        };

        // Find pending request
        const pending = self.pending_requests.get(id) orelse return error.UnknownRequestId;

        // Invoke callback with result (or error)
        if (rpc_response.isError()) {
            // Extract error information
            if (rpc_response.@"error") |err_obj| {
                const code = err_obj.code;
                const message = err_obj.message orelse "Unknown error";
                std.debug.print("[LSP] Server error for {s} (code {d}): {s}\n", .{
                    pending.method,
                    code,
                    message,
                });
            } else {
                std.debug.print("[LSP] Server error for {s}: no error details\n", .{pending.method});
            }
            return error.ServerError;
        }

        // Get result JSON string
        const result_json = rpc_response.result orelse return error.MissingResult;

        // Invoke callback with context
        try pending.callback(pending.callback_ctx, result_json);

        // Remove from pending
        if (self.pending_requests.fetchRemove(id)) |entry| {
            self.allocator.free(entry.value.method);
        }
    }

    /// Handle incoming notification from server
    fn handleNotification(self: *Client, json: []const u8) !void {
        if (self.notification_handler == null) {
            // No handler registered, ignore notification
            return;
        }

        // Parse notification to extract method and params
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidNotification;

        // Extract method
        const method_value = root.object.get("method") orelse return error.MissingMethod;
        if (method_value != .string) return error.InvalidMethod;
        const method = method_value.string;

        // Extract params (optional) and stringify just that portion
        var params_json: []const u8 = "null";
        var params_owned: ?[]u8 = null;
        defer if (params_owned) |owned| self.allocator.free(owned);

        if (root.object.get("params")) |params_value| {
            // Stringify just the params portion
            var params_buf = std.ArrayList(u8).empty;
            defer params_buf.deinit(self.allocator);

            try std.json.Stringify.value(params_value, .{}, params_buf.writer(self.allocator));
            params_owned = try params_buf.toOwnedSlice(self.allocator);
            params_json = params_owned.?;
        }

        // Invoke notification handler
        if (self.notification_handler) |handler| {
            try handler(self.notification_ctx, method, params_json);
        }
    }

    /// Poll for messages from server (non-blocking)
    pub fn poll(self: *Client) !void {
        var process = &(self.process orelse return);

        if (!process.isRunning()) return;

        // Try to read a message (non-blocking via timeout)
        const json = process.readMessage(&self.read_buffer) catch |err| {
            if (err == error.WouldBlock) return; // No message available
            return err;
        };

        // Handle the message (could be response or notification)
        try self.handleMessage(json);
    }
};

/// Initialize request parameters
pub const InitializeParams = struct {
    process_id: ?u32 = null,
    root_uri: ?[]const u8 = null,
    capabilities: ClientCapabilities,
};

/// Client capabilities
pub const ClientCapabilities = struct {
    text_document: ?TextDocumentClientCapabilities = null,
    workspace: ?WorkspaceClientCapabilities = null,
};

/// Text document capabilities
pub const TextDocumentClientCapabilities = struct {
    synchronization: ?struct {
        did_open: bool = true,
        did_change: bool = true,
        did_save: bool = true,
        did_close: bool = true,
    } = .{},
    completion: ?struct {
        dynamic_registration: bool = false,
    } = null,
    hover: ?struct {
        dynamic_registration: bool = false,
    } = null,
};

/// Workspace capabilities
pub const WorkspaceClientCapabilities = struct {
    apply_edit: bool = false,
    workspace_edit: ?struct {
        document_changes: bool = false,
    } = null,
};

/// Initialize request
pub const InitializeRequest = struct {
    id: u32,
    params: InitializeParams,
};

/// Initialize result
pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
};

/// Server capabilities
pub const ServerCapabilities = struct {
    text_document_sync: ?u8 = null,
    hover_provider: bool = false,
    completion_provider: ?struct {
        trigger_characters: ?[]const []const u8 = null,
    } = null,
    definition_provider: bool = false,
    references_provider: bool = false,
    document_formatting_provider: bool = false,
};

// === Tests ===

test "client: init and deinit" {
    const allocator = std.testing.allocator;
    var client = Client.init(allocator);
    defer client.deinit();

    try std.testing.expectEqual(Client.State.uninitialized, client.state);
}

test "client: initialize request" {
    const allocator = std.testing.allocator;
    var client = Client.init(allocator);
    defer client.deinit();

    const params = InitializeParams{
        .capabilities = .{},
    };

    const request = try client.initialize(params);
    try std.testing.expectEqual(@as(u32, 0), request.id);
    try std.testing.expectEqual(Client.State.initializing, client.state);
}

test "client: initialize response" {
    const allocator = std.testing.allocator;
    var client = Client.init(allocator);
    defer client.deinit();

    const params = InitializeParams{
        .capabilities = .{},
    };

    _ = try client.initialize(params);

    const result = InitializeResult{
        .capabilities = .{},
    };

    try client.handleInitializeResponse(result);
    try std.testing.expectEqual(Client.State.initialized, client.state);
    try std.testing.expect(client.isReady());
}

test "client: lifecycle" {
    const allocator = std.testing.allocator;
    var client = Client.init(allocator);
    defer client.deinit();

    // Initialize
    const params = InitializeParams{
        .capabilities = .{},
    };
    _ = try client.initialize(params);

    const result = InitializeResult{
        .capabilities = .{},
    };
    try client.handleInitializeResponse(result);

    // Shutdown
    _ = try client.shutdown();
    try std.testing.expectEqual(Client.State.shutdown, client.state);

    // Exit
    try client.exit();
    try std.testing.expectEqual(Client.State.exited, client.state);
}
