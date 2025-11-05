//! VT100/xterm escape sequence generation
//! Direct terminal control for high-performance rendering

const std = @import("std");

/// ANSI escape sequence prefix
const ESC = "\x1b";
const CSI = ESC ++ "[";

/// Cursor movement commands
pub const Cursor = struct {
    pub const SeqResult = struct {
        data: [32]u8,
        len: usize,

        pub fn slice(self: *const SeqResult) []const u8 {
            return self.data[0..self.len];
        }
    };

    /// Move cursor to position (row, col) - 1-indexed
    pub fn goto(row: u16, col: u16) SeqResult {
        var buf: [32]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, CSI ++ "{d};{d}H", .{ row, col }) catch unreachable;
        return .{ .data = buf, .len = written.len };
    }

    /// Move cursor up by n lines
    pub fn up(n: u16) SeqResult {
        var buf: [32]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, CSI ++ "{d}A", .{n}) catch unreachable;
        return .{ .data = buf, .len = written.len };
    }

    /// Move cursor down by n lines
    pub fn down(n: u16) SeqResult {
        var buf: [32]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, CSI ++ "{d}B", .{n}) catch unreachable;
        return .{ .data = buf, .len = written.len };
    }

    /// Move cursor right by n columns
    pub fn right(n: u16) SeqResult {
        var buf: [32]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, CSI ++ "{d}C", .{n}) catch unreachable;
        return .{ .data = buf, .len = written.len };
    }

    /// Move cursor left by n columns
    pub fn left(n: u16) SeqResult {
        var buf: [32]u8 = undefined;
        const written = std.fmt.bufPrint(&buf, CSI ++ "{d}D", .{n}) catch unreachable;
        return .{ .data = buf, .len = written.len };
    }

    /// Hide cursor
    pub const hide = CSI ++ "?25l";

    /// Show cursor
    pub const show = CSI ++ "?25h";

    /// Save cursor position
    pub const save = CSI ++ "s";

    /// Restore cursor position
    pub const restore = CSI ++ "u";
};

/// Screen manipulation commands
pub const Screen = struct {
    /// Clear entire screen
    pub const clear_all = CSI ++ "2J";

    /// Clear from cursor to end of screen
    pub const clear_below = CSI ++ "0J";

    /// Clear from cursor to beginning of screen
    pub const clear_above = CSI ++ "1J";

    /// Clear current line
    pub const clear_line = CSI ++ "2K";

    /// Clear from cursor to end of line
    pub const clear_line_right = CSI ++ "0K";

    /// Clear from cursor to beginning of line
    pub const clear_line_left = CSI ++ "1K";

    /// Enter alternate screen buffer
    pub const alternate_enter = CSI ++ "?1049h";

    /// Exit alternate screen buffer
    pub const alternate_exit = CSI ++ "?1049l";

    /// Enable mouse tracking (all events)
    pub const mouse_enable = CSI ++ "?1003h" ++ CSI ++ "?1006h";

    /// Disable mouse tracking
    pub const mouse_disable = CSI ++ "?1003l" ++ CSI ++ "?1006l";
};

/// Color and styling
pub const Color = struct {
    /// RGB color (24-bit true color)
    pub const Rgb = struct {
        r: u8,
        g: u8,
        b: u8,

        /// Result type for color escape sequences
        pub const SeqResult = struct {
            data: [32]u8,
            len: usize,

            pub fn slice(self: *const SeqResult) []const u8 {
                return self.data[0..self.len];
            }
        };

        /// Generate foreground color escape sequence
        pub fn fg(self: Rgb) SeqResult {
            var buf: [32]u8 = undefined;
            const written = std.fmt.bufPrint(&buf, CSI ++ "38;2;{d};{d};{d}m", .{ self.r, self.g, self.b }) catch unreachable;
            return .{ .data = buf, .len = written.len };
        }

        /// Generate background color escape sequence
        pub fn bg(self: Rgb) SeqResult {
            var buf: [32]u8 = undefined;
            const written = std.fmt.bufPrint(&buf, CSI ++ "48;2;{d};{d};{d}m", .{ self.r, self.g, self.b }) catch unreachable;
            return .{ .data = buf, .len = written.len };
        }
    };

    /// Standard 16 colors
    pub const Standard = enum(u8) {
        black = 0,
        red = 1,
        green = 2,
        yellow = 3,
        blue = 4,
        magenta = 5,
        cyan = 6,
        white = 7,
        bright_black = 8,
        bright_red = 9,
        bright_green = 10,
        bright_yellow = 11,
        bright_blue = 12,
        bright_magenta = 13,
        bright_cyan = 14,
        bright_white = 15,

        pub const SeqResult = struct {
            data: [16]u8,
            len: usize,

            pub fn slice(self: *const SeqResult) []const u8 {
                return self.data[0..self.len];
            }
        };

        pub fn fg(self: Standard) SeqResult {
            var buf: [16]u8 = undefined;
            const code = if (@intFromEnum(self) < 8) 30 + @intFromEnum(self) else 82 + @intFromEnum(self);
            const written = std.fmt.bufPrint(&buf, CSI ++ "{d}m", .{code}) catch unreachable;
            return .{ .data = buf, .len = written.len };
        }

        pub fn bg(self: Standard) SeqResult {
            var buf: [16]u8 = undefined;
            const code = if (@intFromEnum(self) < 8) 40 + @intFromEnum(self) else 92 + @intFromEnum(self);
            const written = std.fmt.bufPrint(&buf, CSI ++ "{d}m", .{code}) catch unreachable;
            return .{ .data = buf, .len = written.len };
        }
    };

    /// Reset all attributes
    pub const reset = CSI ++ "0m";

    /// Bold/bright
    pub const bold = CSI ++ "1m";

    /// Dim
    pub const dim = CSI ++ "2m";

    /// Italic
    pub const italic = CSI ++ "3m";

    /// Underline
    pub const underline = CSI ++ "4m";

    /// Reverse video
    pub const reverse = CSI ++ "7m";
};

/// Terminal setup and teardown
pub const Terminal = struct {
    /// Enter raw mode (disable line buffering, echo)
    pub fn enterRawMode() !void {
        // Platform-specific implementation needed
        // This is a placeholder for the interface
    }

    /// Exit raw mode
    pub fn exitRawMode() !void {
        // Platform-specific implementation needed
    }

    /// Get terminal size
    pub fn getSize() !struct { width: u16, height: u16 } {
        // Platform-specific implementation needed
        return .{ .width = 80, .height = 24 };
    }
};

test "cursor movement" {
    const goto = Cursor.goto(10, 20);
    try std.testing.expect(std.mem.startsWith(u8, &goto, CSI));
}

test "color generation" {
    const red = Color.Rgb{ .r = 255, .g = 0, .b = 0 };
    const fg_seq = red.fg();
    try std.testing.expect(std.mem.startsWith(u8, &fg_seq, CSI));
}
