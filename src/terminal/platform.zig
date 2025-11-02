//! Platform-specific terminal operations
//! Handles raw mode setup, signal handling, and OS-specific terminal APIs

const std = @import("std");
const builtin = @import("builtin");

/// Platform-specific terminal handle
pub const Terminal = struct {
    original_termios: if (builtin.os.tag != .windows) std.posix.termios else void,
    raw_mode_enabled: bool = false,

    pub fn init() !Terminal {
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

                // Disable output processing
                raw.oflag.OPOST = false;

                // Set character size to 8 bits
                raw.cflag.CSIZE = .CS8;

                // Minimum characters for read
                raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
                // Timeout in deciseconds
                raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;

                try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
                self.raw_mode_enabled = true;
            },

            .windows => {
                // TODO: Windows implementation using SetConsoleMode
                return error.NotImplemented;
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
                // TODO: Windows implementation
                return error.NotImplemented;
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
                // TODO: Windows implementation using GetConsoleScreenBufferInfo
                return error.NotImplemented;
            },

            else => {
                return error.UnsupportedPlatform;
            },
        }
    }

    /// Read raw input from stdin (non-blocking)
    pub fn readInput(self: *const Terminal, buffer: []u8) !usize {
        _ = self;

        const stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO };
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
