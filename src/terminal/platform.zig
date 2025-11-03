//! Platform-specific terminal operations
//! Handles raw mode setup, signal handling, and OS-specific terminal APIs

const std = @import("std");
const builtin = @import("builtin");

/// Platform-specific terminal handle
pub const Terminal = struct {
    original_termios: if (builtin.os.tag != .windows) std.posix.termios else void,
    raw_mode_enabled: bool = false,

    pub fn init() !Terminal {
        // Check if stdin is a TTY before attempting terminal operations
        if (builtin.os.tag != .windows) {
            if (!std.posix.isatty(std.posix.STDIN_FILENO)) {
                return error.NotATerminal;
            }
        }

        return .{
            .original_termios = if (builtin.os.tag != .windows) try std.posix.tcgetattr(std.posix.STDIN_FILENO) else {},
            .raw_mode_enabled = false,
        };
    }

    /// Enter raw mode (disable line buffering, echo, signals)
    pub fn enterRawMode(self: *Terminal) !void {
        if (self.raw_mode_enabled) return;

        switch (builtin.os.tag) {
            .linux, .macos => {
                var raw = self.original_termios;

                // Disable canonical mode, echo, signals
                raw.lflag.ECHO = false;
                raw.lflag.ICANON = false;
                raw.lflag.ISIG = false;
                raw.lflag.IEXTEN = false;

                // Disable input processing
                raw.iflag.IXON = false;
                raw.iflag.ICRNL = false;
                raw.iflag.BRKINT = false;
                raw.iflag.INPCK = false;
                raw.iflag.ISTRIP = false;

                // CRITICAL FIX: Keep output processing enabled for proper newline handling
                // OPOST must be true for \n -> \r\n conversion, otherwise text renders incorrectly
                raw.oflag.OPOST = true;

                // Set character size to 8 bits
                raw.cflag.CSIZE = .CS8;

                // Minimum characters for read (0 = non-blocking with timeout)
                raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
                // Timeout in deciseconds (3 = 0.3s, better balance of responsiveness vs CPU usage)
                raw.cc[@intFromEnum(std.posix.V.TIME)] = 3;

                try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
                self.raw_mode_enabled = true;
            },

            .windows => {
                // Windows implementation pending: Requires SetConsoleMode with
                // ENABLE_VIRTUAL_TERMINAL_PROCESSING flag for VT100 sequences
                std.debug.print("Windows raw mode not yet implemented\n", .{});
                return error.PlatformNotSupported;
            },

            else => {
                return error.UnsupportedPlatform;
            },
        }
    }

    /// Exit raw mode and restore original terminal settings
    pub fn exitRawMode(self: *Terminal) !void {
        if (!self.raw_mode_enabled) return;

        switch (builtin.os.tag) {
            .linux, .macos => {
                try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, self.original_termios);
                self.raw_mode_enabled = false;
            },

            .windows => {
                // Windows implementation pending: Restore original console mode
                return error.PlatformNotSupported;
            },

            else => {
                return error.UnsupportedPlatform;
            },
        }
    }

    /// Get terminal size (width, height)
    pub fn getSize(self: *const Terminal) !struct { width: u16, height: u16 } {
        _ = self;

        switch (builtin.os.tag) {
            .linux, .macos => {
                var winsize: std.posix.winsize = undefined;
                const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
                if (result < 0) {
                    return error.IoctlFailed;
                }

                return .{
                    .width = winsize.col,
                    .height = winsize.row,
                };
            },

            .windows => {
                // Windows implementation pending: GetConsoleScreenBufferInfo
                // Default to standard 80x24 for now
                return .{ .width = 80, .height = 24 };
            },

            else => {
                return error.UnsupportedPlatform;
            },
        }
    }

    /// Read raw input from stdin (non-blocking)
    pub fn readInput(self: *const Terminal, buffer: []u8) !usize {
        _ = self;

        const stdin = std.fs.File.stdin();
        return stdin.read(buffer) catch |err| {
            if (err == error.WouldBlock) return 0;
            return err;
        };
    }
};

test "terminal: init" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const term = try Terminal.init();
    try std.testing.expect(!term.raw_mode_enabled);
}
