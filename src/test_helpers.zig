//! Test helpers and utilities
//! Provides mock implementations and assertion helpers for testing

const std = @import("std");

/// Mock terminal for testing without real terminal I/O
/// Simulates a 2D screen buffer and tracks VT100 escape sequences
pub const MockTerminal = struct {
    input_buffer: std.ArrayList(u8),
    output_buffer: std.ArrayList(u8),
    screen: []u8, // 2D buffer: screen[row * width + col]
    allocator: std.mem.Allocator,
    width: u16 = 80,
    height: u16 = 24,
    cursor_row: u16 = 0,
    cursor_col: u16 = 0,
    cursor_visible: bool = true,
    in_alt_screen: bool = false,

    pub fn init(allocator: std.mem.Allocator) !MockTerminal {
        const w: usize = 80;
        const h: usize = 24;
        const screen = try allocator.alloc(u8, w * h);
        @memset(screen, ' ');

        return .{
            .input_buffer = .{},
            .output_buffer = .{},
            .screen = screen,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MockTerminal) void {
        self.input_buffer.deinit(self.allocator);
        self.output_buffer.deinit(self.allocator);
        self.allocator.free(self.screen);
    }

    /// Queue input for reading
    pub fn queueInput(self: *MockTerminal, input: []const u8) !void {
        try self.input_buffer.appendSlice(self.allocator, input);
    }

    /// Read queued input (simulates terminal read)
    pub fn read(self: *MockTerminal, buffer: []u8) !usize {
        const to_read = @min(buffer.len, self.input_buffer.items.len);
        if (to_read == 0) return 0;

        @memcpy(buffer[0..to_read], self.input_buffer.items[0..to_read]);

        // Remove read bytes from input buffer
        const remaining = self.input_buffer.items[to_read..];
        try self.input_buffer.resize(self.allocator, remaining.len);
        @memcpy(self.input_buffer.items, remaining);

        return to_read;
    }

    /// Write to output buffer and parse VT100 sequences
    pub fn write(self: *MockTerminal, data: []const u8) !usize {
        try self.output_buffer.appendSlice(self.allocator, data);

        // Simple VT100 parsing: track cursor, alt screen, clear
        // This is a basic implementation for testing purposes
        var i: usize = 0;
        while (i < data.len) {
            if (data[i] == '\x1b') {
                // Escape sequence
                if (i + 1 < data.len and data[i + 1] == '[') {
                    // CSI sequence
                    i += 2;
                    // Skip until we hit a letter (command byte)
                    while (i < data.len and !std.ascii.isAlphabetic(data[i])) : (i += 1) {}
                    if (i < data.len) i += 1; // Skip command byte
                } else {
                    i += 1;
                }
            } else if (data[i] == '\n') {
                self.cursor_row +|= 1;
                self.cursor_col = 0;
                i += 1;
            } else if (data[i] == '\r') {
                self.cursor_col = 0;
                i += 1;
            } else if (std.ascii.isPrint(data[i])) {
                // Printable character - add to screen buffer
                if (self.cursor_row < self.height and self.cursor_col < self.width) {
                    const idx = @as(usize, self.cursor_row) * @as(usize, self.width) + @as(usize, self.cursor_col);
                    self.screen[idx] = data[i];
                    self.cursor_col +|= 1;
                }
                i += 1;
            } else {
                i += 1;
            }
        }

        return data.len;
    }

    /// Get all output written so far
    pub fn getOutput(self: *const MockTerminal) []const u8 {
        return self.output_buffer.items;
    }

    /// Clear output buffer
    pub fn clearOutput(self: *MockTerminal) void {
        self.output_buffer.clearRetainingCapacity();
        @memset(self.screen, ' ');
        self.cursor_row = 0;
        self.cursor_col = 0;
    }

    /// Get terminal size
    pub fn getSize(self: *const MockTerminal) struct { width: u16, height: u16 } {
        return .{ .width = self.width, .height = self.height };
    }

    /// Get cursor position
    pub fn getCursorPosition(self: *const MockTerminal) struct { row: u16, col: u16 } {
        return .{ .row = self.cursor_row, .col = self.cursor_col };
    }

    /// Check if output is blank (all spaces or escape sequences only)
    pub fn isBlankScreen(self: *const MockTerminal) bool {
        // Check if screen buffer is all spaces
        for (self.screen) |ch| {
            if (ch != ' ') return false;
        }
        return true;
    }

    /// Check if output contains visible text (not just escape sequences)
    pub fn hasVisibleText(self: *const MockTerminal) bool {
        return !self.isBlankScreen();
    }

    /// Check if output contains a specific string (in screen buffer)
    pub fn screenContains(self: *const MockTerminal, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.screen, needle) != null;
    }

    /// Check if status line is present (checks last row for common status patterns)
    pub fn hasStatusLine(self: *const MockTerminal) bool {
        const last_row_start = (@as(usize, self.height) - 1) * @as(usize, self.width);
        const last_row = self.screen[last_row_start..][0..self.width];

        // Status line typically has mode indicator or filename
        return std.mem.indexOf(u8, last_row, "NORMAL") != null or
            std.mem.indexOf(u8, last_row, "INSERT") != null or
            std.mem.indexOf(u8, last_row, "SELECT") != null or
            std.mem.indexOf(u8, last_row, ".zig") != null or
            std.mem.indexOf(u8, last_row, ".rs") != null;
    }

    /// Check for proper line breaks (no staircase effect)
    pub fn hasCorrectLineBreaks(self: *const MockTerminal) bool {
        // Simple heuristic: check that newlines don't cause staircase
        // Look for common patterns of proper rendering
        const output = self.output_buffer.items;

        // If we have newlines, check they're followed by carriage return or cursor positioning
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, output, i, "\n")) |pos| {
            // After newline, we should have either:
            // - \r (carriage return)
            // - ESC[ (cursor positioning)
            // - Start of next line content
            if (pos + 1 < output.len) {
                const next = output[pos + 1];
                // This is a simplified check - in real output with OPOST enabled,
                // newlines are converted to \r\n
                if (next != '\r' and next != '\x1b') {
                    // Might be staircase effect
                    return false;
                }
            }
            i = pos + 1;
        }
        return true;
    }

    /// Get a specific line from the screen buffer
    pub fn getScreenLine(self: *const MockTerminal, row: u16) []const u8 {
        if (row >= self.height) return &[_]u8{};
        const start = @as(usize, row) * @as(usize, self.width);
        return self.screen[start..][0..self.width];
    }

    /// Count non-space characters in screen (measure of actual content)
    pub fn countVisibleChars(self: *const MockTerminal) usize {
        var count: usize = 0;
        for (self.screen) |ch| {
            if (ch != ' ') count += 1;
        }
        return count;
    }
};

/// Buffer builder for quick test setup
pub const BufferBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BufferBuilder {
        return .{ .allocator = allocator };
    }

    /// Create a buffer with given content
    pub fn withContent(self: BufferBuilder, content: []const u8) !*@import("buffer/manager.zig").Buffer {
        const Buffer = @import("buffer/manager.zig").Buffer;
        var buffer = try Buffer.init(self.allocator, null);

        // Insert content into rope
        try buffer.rope.insert(0, content);

        return buffer;
    }

    /// Create a buffer with multiple lines
    pub fn withLines(self: BufferBuilder, lines: []const []const u8) !*@import("buffer/manager.zig").Buffer {
        var content = std.ArrayList(u8){};
        defer content.deinit(self.allocator);

        for (lines, 0..) |line, i| {
            try content.appendSlice(self.allocator, line);
            if (i < lines.len - 1) {
                try content.append(self.allocator, '\n');
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
            std.debug.print("\nExpected cursor at ({d}, {d}), got ({d}, {d})\n", .{ line, col, cursor.line, cursor.col });
            return error.TestExpectedEqual;
        }
    }
};

/// Mock LSP server responses for testing
pub const MockLSP = struct {
    /// Create a mock completion response
    pub fn completionResponse(allocator: std.mem.Allocator, items: []const []const u8) ![]u8 {
        var response = std.ArrayList(u8){};
        errdefer response.deinit(allocator);

        try response.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[");

        for (items, 0..) |item, i| {
            if (i > 0) try response.append(allocator, ',');
            try response.appendSlice(allocator, "{\"label\":\"");
            try response.appendSlice(allocator, item);
            try response.appendSlice(allocator, "\",\"kind\":3}"); // kind:3 = function
        }

        try response.appendSlice(allocator, "]}");
        return response.toOwnedSlice(allocator);
    }

    /// Create a mock diagnostic notification
    pub fn diagnosticNotification(allocator: std.mem.Allocator, uri: []const u8, line: u32, message: []const u8, severity: u8) ![]u8 {
        var response = std.ArrayList(u8){};
        errdefer response.deinit(allocator);

        try response.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"");
        try response.appendSlice(allocator, uri);
        try response.appendSlice(allocator, "\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":");
        try std.fmt.format(response.writer(allocator), "{d}", .{line});
        try response.appendSlice(allocator, ",\"character\":0},\"end\":{\"line\":");
        try std.fmt.format(response.writer(allocator), "{d}", .{line});
        try response.appendSlice(allocator, ",\"character\":10}},\"severity\":");
        try std.fmt.format(response.writer(allocator), "{d}", .{severity});
        try response.appendSlice(allocator, ",\"message\":\"");
        try response.appendSlice(allocator, message);
        try response.appendSlice(allocator, "\"}]}}");

        return response.toOwnedSlice(allocator);
    }

    /// Create a mock hover response
    pub fn hoverResponse(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
        var response = std.ArrayList(u8){};
        errdefer response.deinit(allocator);

        try response.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"");
        try response.appendSlice(allocator, content);
        try response.appendSlice(allocator, "\"}}}");

        return response.toOwnedSlice(allocator);
    }
};

/// Test persona definitions
pub const Persona = enum {
    developer, // Code-heavy workflow with LSP
    writer, // Prose editing with search/macros
    sysadmin, // Config file editing with splits

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
