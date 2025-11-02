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
        callback: *const fn (result: []const u8) anyerror!void,
    };

    /// Initialize LSP client with server process
    pub fn init(allocator: std.mem.Allocator, process: ?Process) Client {
        return .{
            .allocator = allocator,
            .state = .uninitialized,
            .request_id = 0,
            .pending_requests = std.AutoHashMap(u32, PendingRequest).init(allocator),
            .process = process,
            .read_buffer = undefined,
        };
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
        callback: *const fn (result: []const u8) anyerror!void,
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

    /// Handle incoming response from server
    pub fn handleResponse(self: *Client, json: []const u8) !void {
        // Parse JSON-RPC response using zigjr
        var rpc_response = try zigjr.parseRpcResponse(self.allocator, json);
        defer rpc_response.deinit();

        // Extract ID
        const id: u32 = switch (rpc_response.id) {
            .num => |n| @intCast(n),
            .str => return error.InvalidResponseId,
        };

        // Find pending request
        const pending = self.pending_requests.get(id) orelse return error.UnknownRequestId;

        // Invoke callback with result (or error)
        if (rpc_response.isError()) {
            // TODO: Extract error message and pass to callback
            return error.ServerError;
        }

        // Get result JSON string
        const result_json = rpc_response.result orelse return error.MissingResult;

        // Invoke callback
        try pending.callback(result_json);

        // Remove from pending
        if (self.pending_requests.fetchRemove(id)) |entry| {
            self.allocator.free(entry.value.method);
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

        // Handle the message
        try self.handleResponse(json);
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
