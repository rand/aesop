//! Generic prompt system for user input
//! Handles text, character, and number input with history

const std = @import("std");

/// Prompt type determines input validation and handling
pub const PromptType = enum {
    text,      // Free-form text input
    character, // Single character input
    number,    // Integer input
    choice,    // Y/N or multiple choice
};

/// Prompt state and input buffer
pub const Prompt = struct {
    prompt_text: [256]u8 = undefined,
    prompt_len: usize = 0,
    input_buffer: [1024]u8 = undefined,
    input_len: usize = 0,
    cursor_pos: usize = 0,
    visible: bool = false,
    prompt_type: PromptType = .text,
    history: std.ArrayList([]const u8),
    history_index: ?usize = null,
    allocator: std.mem.Allocator,
    callback: ?*const fn (input: []const u8) void = null,

    pub fn init(allocator: std.mem.Allocator) Prompt {
        return .{
            .allocator = allocator,
            .history = std.ArrayList([]const u8).empty,
        };
    }

    pub fn deinit(self: *Prompt) void {
        // Free history entries
        for (self.history.items) |entry| {
            self.allocator.free(entry);
        }
        self.history.deinit(self.allocator);
    }

    /// Show prompt with given text and type
    pub fn show(self: *Prompt, prompt_text: []const u8, prompt_type: PromptType) void {
        if (prompt_text.len > self.prompt_text.len) return;

        @memcpy(self.prompt_text[0..prompt_text.len], prompt_text);
        self.prompt_len = prompt_text.len;
        self.input_len = 0;
        self.cursor_pos = 0;
        self.visible = true;
        self.prompt_type = prompt_type;
        self.history_index = null;
    }

    /// Hide prompt and clear state
    pub fn hide(self: *Prompt) void {
        self.visible = false;
        self.input_len = 0;
        self.cursor_pos = 0;
        self.history_index = null;
    }

    /// Add character to input buffer
    pub fn addChar(self: *Prompt, ch: u8) !void {
        if (self.input_len >= self.input_buffer.len) return error.BufferFull;

        // For character type, only allow single character
        if (self.prompt_type == .character) {
            self.input_buffer[0] = ch;
            self.input_len = 1;
            self.cursor_pos = 1;
            return;
        }

        // For number type, only allow digits, minus, and decimal
        if (self.prompt_type == .number) {
            if (!(ch >= '0' and ch <= '9') and ch != '-' and ch != '.') {
                return error.InvalidCharacter;
            }
        }

        // Insert character at cursor position
        if (self.cursor_pos < self.input_len) {
            // Shift everything right
            var i = self.input_len;
            while (i > self.cursor_pos) : (i -= 1) {
                self.input_buffer[i] = self.input_buffer[i - 1];
            }
        }

        self.input_buffer[self.cursor_pos] = ch;
        self.input_len += 1;
        self.cursor_pos += 1;
    }

    /// Remove character before cursor (backspace)
    pub fn backspace(self: *Prompt) void {
        if (self.cursor_pos == 0) return;

        // Shift everything left
        var i = self.cursor_pos - 1;
        while (i < self.input_len - 1) : (i += 1) {
            self.input_buffer[i] = self.input_buffer[i + 1];
        }

        self.input_len -= 1;
        self.cursor_pos -= 1;
    }

    /// Delete character at cursor (delete key)
    pub fn deleteChar(self: *Prompt) void {
        if (self.cursor_pos >= self.input_len) return;

        // Shift everything left
        var i = self.cursor_pos;
        while (i < self.input_len - 1) : (i += 1) {
            self.input_buffer[i] = self.input_buffer[i + 1];
        }

        self.input_len -= 1;
    }

    /// Move cursor left
    pub fn moveCursorLeft(self: *Prompt) void {
        if (self.cursor_pos > 0) {
            self.cursor_pos -= 1;
        }
    }

    /// Move cursor right
    pub fn moveCursorRight(self: *Prompt) void {
        if (self.cursor_pos < self.input_len) {
            self.cursor_pos += 1;
        }
    }

    /// Move cursor to start
    pub fn moveCursorStart(self: *Prompt) void {
        self.cursor_pos = 0;
    }

    /// Move cursor to end
    pub fn moveCursorEnd(self: *Prompt) void {
        self.cursor_pos = self.input_len;
    }

    /// Get current input
    pub fn getInput(self: *const Prompt) []const u8 {
        return self.input_buffer[0..self.input_len];
    }

    /// Get prompt text
    pub fn getPromptText(self: *const Prompt) []const u8 {
        return self.prompt_text[0..self.prompt_len];
    }

    /// Submit input and add to history
    pub fn submit(self: *Prompt) ![]const u8 {
        const input = self.getInput();

        // Don't add empty inputs to history
        if (input.len > 0) {
            const input_copy = try self.allocator.dupe(u8, input);
            try self.history.append(self.allocator, input_copy);
        }

        return input;
    }

    /// Navigate to previous history item
    pub fn historyPrev(self: *Prompt) void {
        if (self.history.items.len == 0) return;

        if (self.history_index) |idx| {
            if (idx > 0) {
                self.history_index = idx - 1;
            }
        } else {
            // Start from end
            self.history_index = self.history.items.len - 1;
        }

        if (self.history_index) |idx| {
            const entry = self.history.items[idx];
            const len = @min(entry.len, self.input_buffer.len);
            @memcpy(self.input_buffer[0..len], entry[0..len]);
            self.input_len = len;
            self.cursor_pos = len;
        }
    }

    /// Navigate to next history item
    pub fn historyNext(self: *Prompt) void {
        if (self.history_index == null) return;

        const idx = self.history_index.?;
        if (idx + 1 < self.history.items.len) {
            self.history_index = idx + 1;
            const entry = self.history.items[idx + 1];
            const len = @min(entry.len, self.input_buffer.len);
            @memcpy(self.input_buffer[0..len], entry[0..len]);
            self.input_len = len;
            self.cursor_pos = len;
        } else {
            // Back to current input
            self.history_index = null;
            self.input_len = 0;
            self.cursor_pos = 0;
        }
    }

    /// Parse input as integer
    pub fn parseNumber(self: *const Prompt) !i64 {
        const input = self.getInput();
        return try std.fmt.parseInt(i64, input, 10);
    }

    /// Get single character input
    pub fn getCharacter(self: *const Prompt) ?u8 {
        if (self.input_len > 0) {
            return self.input_buffer[0];
        }
        return null;
    }
};

// === Tests ===

test "prompt: basic input" {
    const allocator = std.testing.allocator;
    var prompt = Prompt.init(allocator);
    defer prompt.deinit();

    prompt.show("Enter text: ", .text);
    try std.testing.expect(prompt.visible);

    try prompt.addChar('h');
    try prompt.addChar('i');

    const input = prompt.getInput();
    try std.testing.expect(std.mem.eql(u8, input, "hi"));
}

test "prompt: backspace" {
    const allocator = std.testing.allocator;
    var prompt = Prompt.init(allocator);
    defer prompt.deinit();

    prompt.show("Enter: ", .text);
    try prompt.addChar('a');
    try prompt.addChar('b');
    try prompt.addChar('c');

    prompt.backspace();
    const input = prompt.getInput();
    try std.testing.expect(std.mem.eql(u8, input, "ab"));
}

test "prompt: number validation" {
    const allocator = std.testing.allocator;
    var prompt = Prompt.init(allocator);
    defer prompt.deinit();

    prompt.show("Enter number: ", .number);
    try prompt.addChar('1');
    try prompt.addChar('2');
    try prompt.addChar('3');

    const num = try prompt.parseNumber();
    try std.testing.expectEqual(@as(i64, 123), num);
}
