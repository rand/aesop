//! Main rendering system
//! Coordinates terminal output, damage tracking, and frame rendering

const std = @import("std");
const vt100 = @import("../terminal/vt100.zig");
const platform = @import("../terminal/platform.zig");
const buffer = @import("buffer.zig");

pub const OutputBuffer = buffer.OutputBuffer;
pub const Cell = buffer.Cell;
pub const Color = buffer.Color;
pub const Attrs = buffer.Attrs;

/// Main renderer - manages terminal output and rendering loop
const WRITE_BUF_SIZE = 65536;

pub const Renderer = struct {
    terminal: platform.Terminal,
    output: OutputBuffer,
    stdout: std.fs.File,
    write_buf: [WRITE_BUF_SIZE]u8,
    write_pos: usize,
    current_fg: Color = .default,
    current_bg: Color = .default,
    current_attrs: Attrs = .{},

    /// Initialize renderer
    pub fn init(allocator: std.mem.Allocator) !Renderer {
        const term = try platform.Terminal.init();
        const size = try term.getSize();

        const stdout_file = std.fs.File.stdout();

        var output_buf = try OutputBuffer.init(allocator, size.width, size.height);
        // CRITICAL FIX: Mark all lines dirty on init to ensure first render displays
        // Without this, computeDamage() sees both buffers as identical (all zeros)
        // and renders nothing, resulting in a blank screen
        output_buf.markAllDirty();

        return .{
            .terminal = term,
            .output = output_buf,
            .stdout = stdout_file,
            .write_buf = undefined,
            .write_pos = 0,
        };
    }

    /// Clean up renderer
    pub fn deinit(self: *Renderer) void {
        self.output.deinit();
    }

    /// Enter raw mode and setup terminal
    pub fn enterRawMode(self: *Renderer) !void {
        try self.terminal.enterRawMode();

        // Enter alternate screen
        try self.write(vt100.Screen.alternate_enter);

        // Set UTF-8 mode explicitly
        try self.write("\x1b%G");

        // Clear screen and home cursor
        try self.write(vt100.Screen.clear_all);
        const home = vt100.Cursor.goto(1, 1);
        try self.write(home.slice());

        // Hide cursor (will be repositioned during render)
        try self.write(vt100.Cursor.hide);

        try self.flush();
    }

    /// Exit raw mode and restore terminal
    pub fn exitRawMode(self: *Renderer) !void {
        // Show cursor
        try self.write(vt100.Cursor.show);

        // Exit alternate screen
        try self.write(vt100.Screen.alternate_exit);

        // Reset colors
        try self.write(vt100.Color.reset);

        try self.flush();

        try self.terminal.exitRawMode();
    }

    /// Render current frame
    pub fn render(self: *Renderer) !void {
        // Compute which lines changed
        self.output.computeDamage();

        // Render only dirty lines
        var iter = self.output.dirtyIterator();
        while (iter.next()) |row| {
            try self.renderLine(row);
        }

        // Swap buffers
        self.output.swap();

        // Flush output
        try self.flush();
    }

    /// Render a single line
    fn renderLine(self: *Renderer, row: u16) !void {
        // Move cursor to beginning of line
        const goto = vt100.Cursor.goto(row + 1, 1);
        try self.write(goto.slice());

        // Reset attributes at start of line
        self.current_fg = .default;
        self.current_bg = .default;
        self.current_attrs = .{};
        try self.write(vt100.Color.reset);

        // Render each cell in the line
        for (0..self.output.width) |col| {
            const cell = self.output.getCell(row, @intCast(col)) orelse continue;

            // Update colors if changed
            if (!cell.fg.eql(self.current_fg)) {
                try self.emitFgColor(cell.fg);
                self.current_fg = cell.fg;
            }

            if (!cell.bg.eql(self.current_bg)) {
                try self.emitBgColor(cell.bg);
                self.current_bg = cell.bg;
            }

            // Update attributes if changed
            if (!std.meta.eql(cell.attrs, self.current_attrs)) {
                try self.emitAttrs(cell.attrs);
                self.current_attrs = cell.attrs;
            }

            // Output character
            var utf8_buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cell.char, &utf8_buf) catch |err| {
                // If encoding fails, write a space as fallback
                std.debug.print("UTF-8 encode error for char {}: {}\n", .{ cell.char, err });
                try self.write(" ");
                continue;
            };
            try self.write(utf8_buf[0..len]);
        }
    }

    fn emitFgColor(self: *Renderer, color: Color) !void {
        switch (color) {
            .default => try self.write("\x1b[39m"),
            .standard => |s| {
                const seq = s.fg();
                try self.write(seq.slice());
            },
            .rgb => |r| {
                const seq = r.fg();
                try self.write(seq.slice());
            },
        }
    }

    fn emitBgColor(self: *Renderer, color: Color) !void {
        switch (color) {
            .default => try self.write("\x1b[49m"),
            .standard => |s| {
                const seq = s.bg();
                try self.write(seq.slice());
            },
            .rgb => |r| {
                const seq = r.bg();
                try self.write(seq.slice());
            },
        }
    }

    fn emitAttrs(self: *Renderer, attrs: Attrs) !void {
        // Reset first
        try self.write(vt100.Color.reset);

        if (attrs.bold) try self.write(vt100.Color.bold);
        if (attrs.dim) try self.write(vt100.Color.dim);
        if (attrs.italic) try self.write(vt100.Color.italic);
        if (attrs.underline) try self.write(vt100.Color.underline);
        if (attrs.reverse) try self.write(vt100.Color.reverse);
    }

    fn write(self: *Renderer, data: []const u8) !void {
        const remaining = self.write_buf.len - self.write_pos;
        if (data.len > remaining) {
            // Flush if buffer is full
            try self.flush();
        }

        @memcpy(self.write_buf[self.write_pos..][0..data.len], data);
        self.write_pos += data.len;
    }

    fn flush(self: *Renderer) !void {
        if (self.write_pos > 0) {
            try self.stdout.writeAll(self.write_buf[0..self.write_pos]);
            self.write_pos = 0;
        }
    }

    /// Clear the output buffer
    pub fn clear(self: *Renderer) void {
        self.output.clear();
    }

    /// Write text to the output buffer
    /// max_width: Optional maximum column to stop rendering at (null = use terminal width)
    pub fn writeText(self: *Renderer, row: u16, col: u16, text: []const u8, fg: Color, bg: Color, attrs: Attrs, max_width: ?u16) void {
        self.output.writeText(row, col, text, fg, bg, attrs, max_width);
    }

    /// Get terminal size
    pub fn getSize(self: *const Renderer) struct { width: u16, height: u16 } {
        return .{ .width = self.output.width, .height = self.output.height };
    }

    /// Handle terminal resize
    pub fn handleResize(self: *Renderer) !void {
        const new_size = try self.terminal.getSize();
        try self.output.resize(new_size.width, new_size.height);
        self.output.markAllDirty();
    }
};

test "renderer: init and deinit" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();

    const size = renderer.getSize();
    try std.testing.expect(size.width > 0);
    try std.testing.expect(size.height > 0);
}
