//! Test helpers and utilities
//! Provides mock implementations and assertion helpers for testing

const std = @import("std");

/// Mock terminal for testing without real terminal I/O
pub const MockTerminal = struct {
    input_buffer: std.ArrayList(u8),
    output_buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,
    width: u16 = 80,
    height: u16 = 24,

    pub fn init(allocator: std.mem.Allocator) MockTerminal {
        return .{
            .input_buffer = std.ArrayList(u8).init(allocator),
            .output_buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MockTerminal) void {
        self.input_buffer.deinit();
        self.output_buffer.deinit();
    }

    /// Queue input for reading
    pub fn queueInput(self: *MockTerminal, input: []const u8) !void {
        try self.input_buffer.appendSlice(input);
    }

    /// Read queued input (simulates terminal read)
    pub fn read(self: *MockTerminal, buffer: []u8) !usize {
        const to_read = @min(buffer.len, self.input_buffer.items.len);
        if (to_read == 0) return 0;

        @memcpy(buffer[0..to_read], self.input_buffer.items[0..to_read]);

        // Remove read bytes from input buffer
        const remaining = self.input_buffer.items[to_read..];
        try self.input_buffer.resize(remaining.len);
        @memcpy(self.input_buffer.items, remaining);

        return to_read;
    }

    /// Write to output buffer (simulates terminal write)
    pub fn write(self: *MockTerminal, data: []const u8) !usize {
        try self.output_buffer.appendSlice(data);
        return data.len;
    }

    /// Get all output written so far
    pub fn getOutput(self: *const MockTerminal) []const u8 {
        return self.output_buffer.items;
    }

    /// Clear output buffer
    pub fn clearOutput(self: *MockTerminal) void {
        self.output_buffer.clearRetainingCapacity();
    }

    /// Get terminal size
    pub fn getSize(self: *const MockTerminal) struct { width: u16, height: u16 } {
        return .{ .width = self.width, .height = self.height };
    }
};

/// Buffer builder for quick test setup
pub const BufferBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BufferBuilder {
        return .{ .allocator = allocator };
    }

    /// Create a buffer with given content
    pub fn withContent(self: BufferBuilder, content: []const u8) !*@import("../src/buffer/manager.zig").Buffer {
        const Buffer = @import("../src/buffer/manager.zig").Buffer;
        var buffer = try Buffer.init(self.allocator, null);

        // Insert content into rope
        try buffer.rope.insert(0, content);

        return buffer;
    }

    /// Create a buffer with multiple lines
    pub fn withLines(self: BufferBuilder, lines: []const []const u8) !*@import("../src/buffer/manager.zig").Buffer {
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        for (lines, 0..) |line, i| {
            try content.appendSlice(line);
            if (i < lines.len - 1) {
                try content.append('\n');
            }
        }

        return try self.withContent(content.items);
    }
};

/// Custom assertion helpers
pub const Assertions = struct {
    /// Assert that two slices are equal with detailed error message
    pub fn expectEqualSlices(comptime T: type, expected: []const T, actual: []const T) !void {
        if (!std.mem.eql(T, expected, actual)) {
            std.debug.print("\nExpected:\n{any}\n\nActual:\n{any}\n", .{ expected, actual });
            return error.TestExpectedEqual;
        }
    }

    /// Assert that string contains substring
    pub fn expectContains(haystack: []const u8, needle: []const u8) !void {
        if (std.mem.indexOf(u8, haystack, needle) == null) {
            std.debug.print("\nExpected to find '{s}' in '{s}'\n", .{ needle, haystack });
            return error.TestExpectedContains;
        }
    }

    /// Assert that buffer has expected line count
    pub fn expectLineCount(buffer: anytype, expected: usize) !void {
        const actual = buffer.lineCount();
        if (actual != expected) {
            std.debug.print("\nExpected {d} lines, got {d}\n", .{ expected, actual });
            return error.TestExpectedEqual;
        }
    }

    /// Assert that cursor is at expected position
    pub fn expectCursorAt(cursor: anytype, line: usize, col: usize) !void {
        if (cursor.line != line or cursor.col != col) {
            std.debug.print("\nExpected cursor at ({d}, {d}), got ({d}, {d})\n",
                .{ line, col, cursor.line, cursor.col });
            return error.TestExpectedEqual;
        }
    }
};

/// Mock LSP server responses for testing
pub const MockLSP = struct {
    /// Create a mock completion response
    pub fn completionResponse(allocator: std.mem.Allocator, items: []const []const u8) ![]u8 {
        var response = std.ArrayList(u8).init(allocator);
        errdefer response.deinit();

        try response.appendSlice("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[");

        for (items, 0..) |item, i| {
            if (i > 0) try response.append(',');
            try response.appendSlice("{\"label\":\"");
            try response.appendSlice(item);
            try response.appendSlice("\",\"kind\":3}"); // kind:3 = function
        }

        try response.appendSlice("]}");
        return response.toOwnedSlice();
    }

    /// Create a mock diagnostic notification
    pub fn diagnosticNotification(allocator: std.mem.Allocator, uri: []const u8,
                                   line: u32, message: []const u8, severity: u8) ![]u8 {
        var response = std.ArrayList(u8).init(allocator);
        errdefer response.deinit();

        try response.appendSlice("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"");
        try response.appendSlice(uri);
        try response.appendSlice("\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":");
        try std.fmt.format(response.writer(), "{d}", .{line});
        try response.appendSlice(",\"character\":0},\"end\":{\"line\":");
        try std.fmt.format(response.writer(), "{d}", .{line});
        try response.appendSlice(",\"character\":10}},\"severity\":");
        try std.fmt.format(response.writer(), "{d}", .{severity});
        try response.appendSlice(",\"message\":\"");
        try response.appendSlice(message);
        try response.appendSlice("\"}]}}");

        return response.toOwnedSlice();
    }

    /// Create a mock hover response
    pub fn hoverResponse(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
        var response = std.ArrayList(u8).init(allocator);
        errdefer response.deinit();

        try response.appendSlice("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"");
        try response.appendSlice(content);
        try response.appendSlice("\"}}}");

        return response.toOwnedSlice();
    }
};

/// Test persona definitions
pub const Persona = enum {
    developer,  // Code-heavy workflow with LSP
    writer,     // Prose editing with search/macros
    sysadmin,   // Config file editing with splits

    /// Get sample workflow for persona
    pub fn getWorkflow(self: Persona) []const u8 {
        return switch (self) {
            .developer => "Open Zig file → Navigate to function → Trigger completion → Insert code → Save → Format → View diagnostics → Go to definition → Rename symbol",
            .writer => "Open markdown → Navigate paragraphs → Search with regex → Multi-cursor edit → Undo/redo → Set marks → Record macro → Replay → Save",
            .sysadmin => "File finder → Open config → Split window → Edit both → Buffer switch → Search across files → Set bookmarks → Close splits → Save all",
        };
    }

    /// Get sample file content for persona
    pub fn getSampleContent(self: Persona, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .developer => try allocator.dupe(u8,
                \\const std = @import("std");
                \\
                \\pub fn main() !void {
                \\    const allocator = std.heap.page_allocator;
                \\    const result = try calculate(allocator, 42);
                \\    std.debug.print("Result: {d}\n", .{result});
                \\}
                \\
                \\fn calculate(allocator: std.mem.Allocator, value: i32) !i32 {
                \\    _ = allocator;
                \\    return value * 2;
                \\}
            ),
            .writer => try allocator.dupe(u8,
                \\# Document Title
                \\
                \\This is a sample document for testing prose editing capabilities.
                \\It contains multiple paragraphs with various formatting.
                \\
                \\## Section 1
                \\
                \\Lorem ipsum dolor sit amet, consectetur adipiscing elit.
                \\Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
                \\
                \\## Section 2
                \\
                \\More content here with **bold** and *italic* text.
            ),
            .sysadmin => try allocator.dupe(u8,
                \\# Configuration file
                \\server_port = 8080
                \\server_host = "localhost"
                \\
                \\[database]
                \\connection_string = "postgresql://localhost/mydb"
                \\pool_size = 10
                \\
                \\[logging]
                \\level = "info"
                \\output = "/var/log/app.log"
            ),
        };
    }
};

// === Tests for helpers ===

test "mock terminal: queue and read input" {
    const allocator = std.testing.allocator;
    var terminal = MockTerminal.init(allocator);
    defer terminal.deinit();

    try terminal.queueInput("hello");

    var buffer: [10]u8 = undefined;
    const n = try terminal.read(&buffer);

    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualStrings("hello", buffer[0..n]);
}

test "mock terminal: write and get output" {
    const allocator = std.testing.allocator;
    var terminal = MockTerminal.init(allocator);
    defer terminal.deinit();

    _ = try terminal.write("test output");
    try std.testing.expectEqualStrings("test output", terminal.getOutput());
}

test "buffer builder: create with content" {
    const allocator = std.testing.allocator;
    const builder = BufferBuilder.init(allocator);

    var buffer = try builder.withContent("hello world");
    defer buffer.deinit();

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("hello world", content);
}

test "mock LSP: completion response" {
    const allocator = std.testing.allocator;
    const items = [_][]const u8{ "foo", "bar", "baz" };

    const response = try MockLSP.completionResponse(allocator, &items);
    defer allocator.free(response);

    try Assertions.expectContains(response, "\"label\":\"foo\"");
    try Assertions.expectContains(response, "\"label\":\"bar\"");
    try Assertions.expectContains(response, "\"label\":\"baz\"");
}

test "persona: get workflow" {
    const workflow = Persona.developer.getWorkflow();
    try std.testing.expect(workflow.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, workflow, "LSP") != null);
}
