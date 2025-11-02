//! Terminal output buffer with damage tracking
//! Double-buffering for flicker-free updates
//! Character-cell based rendering (not pixel-based)

const std = @import("std");
const vt100 = @import("../terminal/vt100.zig");

/// A single character cell in the terminal
pub const Cell = struct {
    char: u21 = ' ',
    fg: Color = Color.default,
    bg: Color = Color.default,
    attrs: Attrs = Attrs{},

    pub fn eql(self: Cell, other: Cell) bool {
        return self.char == other.char and
            self.fg.eql(other.fg) and
            self.bg.eql(other.bg) and
            std.meta.eql(self.attrs, other.attrs);
    }
};

/// Color representation
pub const Color = union(enum) {
    default: void,
    standard: vt100.Color.Standard,
    rgb: vt100.Color.Rgb,

    pub fn eql(self: Color, other: Color) bool {
        return switch (self) {
            .default => other == .default,
            .standard => |s| other == .standard and s == other.standard,
            .rgb => |r| other == .rgb and
                r.r == other.rgb.r and
                r.g == other.rgb.g and
                r.b == other.rgb.b,
        };
    }

    /// Common color constants
    pub const black = Color{ .standard = vt100.Color.Standard.black };
    pub const red = Color{ .standard = vt100.Color.Standard.red };
    pub const green = Color{ .standard = vt100.Color.Standard.green };
    pub const yellow = Color{ .standard = vt100.Color.Standard.yellow };
    pub const blue = Color{ .standard = vt100.Color.Standard.blue };
    pub const magenta = Color{ .standard = vt100.Color.Standard.magenta };
    pub const cyan = Color{ .standard = vt100.Color.Standard.cyan };
    pub const white = Color{ .standard = vt100.Color.Standard.white };
    pub const bright_black = Color{ .standard = vt100.Color.Standard.bright_black };
    pub const bright_red = Color{ .standard = vt100.Color.Standard.bright_red };
    pub const bright_green = Color{ .standard = vt100.Color.Standard.bright_green };
    pub const bright_yellow = Color{ .standard = vt100.Color.Standard.bright_yellow };
    pub const bright_blue = Color{ .standard = vt100.Color.Standard.bright_blue };
    pub const bright_magenta = Color{ .standard = vt100.Color.Standard.bright_magenta };
    pub const bright_cyan = Color{ .standard = vt100.Color.Standard.bright_cyan };
    pub const bright_white = Color{ .standard = vt100.Color.Standard.bright_white };
};

/// Text attributes
pub const Attrs = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,
};

/// Output buffer with damage tracking
pub const OutputBuffer = struct {
    width: u16,
    height: u16,
    screen_buf: []Cell,      // Current screen state
    back_buf: []Cell,        // Next frame buffer
    dirty_lines: []bool,     // Track which lines need redraw
    allocator: std.mem.Allocator,

    /// Initialize output buffer with given dimensions
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !OutputBuffer {
        const size = @as(usize, width) * @as(usize, height);

        const screen_buf = try allocator.alloc(Cell, size);
        @memset(screen_buf, Cell{});

        const back_buf = try allocator.alloc(Cell, size);
        @memset(back_buf, Cell{});

        const dirty_lines = try allocator.alloc(bool, height);
        @memset(dirty_lines, true); // Initially all dirty

        return .{
            .width = width,
            .height = height,
            .screen_buf = screen_buf,
            .back_buf = back_buf,
            .dirty_lines = dirty_lines,
            .allocator = allocator,
        };
    }

    /// Clean up and free memory
    pub fn deinit(self: *OutputBuffer) void {
        self.allocator.free(self.screen_buf);
        self.allocator.free(self.back_buf);
        self.allocator.free(self.dirty_lines);
    }

    /// Resize buffer (allocates new buffers)
    pub fn resize(self: *OutputBuffer, new_width: u16, new_height: u16) !void {
        const new_size = @as(usize, new_width) * @as(usize, new_height);

        // Allocate new buffers
        const new_screen = try self.allocator.alloc(Cell, new_size);
        @memset(new_screen, Cell{});

        const new_back = try self.allocator.alloc(Cell, new_size);
        @memset(new_back, Cell{});

        const new_dirty = try self.allocator.alloc(bool, new_height);
        @memset(new_dirty, true);

        // Copy old content (as much as fits)
        const copy_height = @min(self.height, new_height);
        const copy_width = @min(self.width, new_width);

        for (0..copy_height) |row| {
            const old_start = row * self.width;
            const new_start = row * new_width;

            for (0..copy_width) |col| {
                new_screen[new_start + col] = self.screen_buf[old_start + col];
                new_back[new_start + col] = self.back_buf[old_start + col];
            }
        }

        // Free old buffers
        self.allocator.free(self.screen_buf);
        self.allocator.free(self.back_buf);
        self.allocator.free(self.dirty_lines);

        // Update fields
        self.width = new_width;
        self.height = new_height;
        self.screen_buf = new_screen;
        self.back_buf = new_back;
        self.dirty_lines = new_dirty;
    }

    /// Set a cell in the back buffer
    pub fn setCell(self: *OutputBuffer, row: u16, col: u16, cell: Cell) void {
        if (row >= self.height or col >= self.width) return;

        const idx = @as(usize, row) * @as(usize, self.width) + @as(usize, col);
        self.back_buf[idx] = cell;
    }

    /// Get a cell from the back buffer
    pub fn getCell(self: *const OutputBuffer, row: u16, col: u16) ?Cell {
        if (row >= self.height or col >= self.width) return null;

        const idx = @as(usize, row) * @as(usize, self.width) + @as(usize, col);
        return self.back_buf[idx];
    }

    /// Write line number in gutter
    pub fn writeLineNumber(self: *OutputBuffer, row: u16, line_num: usize, gutter_width: u16) void {
        var buf: [16]u8 = undefined;
        const num_str = std.fmt.bufPrint(&buf, "{d}", .{line_num}) catch return;

        // Right-align line number in gutter
        const padding = if (gutter_width > num_str.len)
            gutter_width - @as(u16, @intCast(num_str.len))
        else
            0;

        // Write line number with dimmed color
        self.writeText(
            row,
            padding,
            num_str,
            Color.bright_black, // Gray for line numbers
            Color.default,
            Attrs{},
        );

        // Add separator after gutter
        if (gutter_width > 0 and gutter_width - 1 < self.width) {
            self.setCell(row, gutter_width - 1, .{
                .char = ' ',
                .fg = Color.default,
                .bg = Color.default,
                .attrs = Attrs{},
            });
        }
    }

    /// Write text at position with given style
    pub fn writeText(self: *OutputBuffer, row: u16, col: u16, text: []const u8, fg: Color, bg: Color, attrs: Attrs) void {
        var current_col = col;
        var i: usize = 0;

        while (i < text.len and current_col < self.width) {
            const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            if (i + cp_len > text.len) break;

            const codepoint = std.unicode.utf8Decode(text[i..][0..cp_len]) catch ' ';

            self.setCell(row, current_col, .{
                .char = codepoint,
                .fg = fg,
                .bg = bg,
                .attrs = attrs,
            });

            current_col += 1;
            i += cp_len;
        }
    }

    /// Clear the back buffer
    pub fn clear(self: *OutputBuffer) void {
        @memset(self.back_buf, Cell{});
        @memset(self.dirty_lines, true);
    }

    /// Mark a line as dirty (needs redraw)
    pub fn markDirty(self: *OutputBuffer, row: u16) void {
        if (row < self.height) {
            self.dirty_lines[row] = true;
        }
    }

    /// Mark all lines as dirty
    pub fn markAllDirty(self: *OutputBuffer) void {
        @memset(self.dirty_lines, true);
    }

    /// Compute damage (which lines changed)
    pub fn computeDamage(self: *OutputBuffer) void {
        for (0..self.height) |row| {
            const row_start = row * self.width;
            const row_end = row_start + self.width;

            // Compare screen_buf and back_buf for this line
            const screen_line = self.screen_buf[row_start..row_end];
            const back_line = self.back_buf[row_start..row_end];

            var line_changed = false;
            for (screen_line, back_line) |screen_cell, back_cell| {
                if (!screen_cell.eql(back_cell)) {
                    line_changed = true;
                    break;
                }
            }

            self.dirty_lines[row] = line_changed;
        }
    }

    /// Swap buffers (back becomes screen)
    pub fn swap(self: *OutputBuffer) void {
        std.mem.swap([]Cell, &self.screen_buf, &self.back_buf);

        // Clear dirty flags
        @memset(self.dirty_lines, false);
    }

    /// Get iterator over dirty lines
    pub fn dirtyIterator(self: *const OutputBuffer) DirtyIterator {
        return .{
            .dirty_lines = self.dirty_lines,
            .current = 0,
        };
    }

    pub const DirtyIterator = struct {
        dirty_lines: []const bool,
        current: usize,

        pub fn next(self: *DirtyIterator) ?u16 {
            while (self.current < self.dirty_lines.len) {
                const row = self.current;
                self.current += 1;

                if (self.dirty_lines[row]) {
                    return @intCast(row);
                }
            }
            return null;
        }
    };
};

test "output buffer: init and deinit" {
    const allocator = std.testing.allocator;
    var buf = try OutputBuffer.init(allocator, 80, 24);
    defer buf.deinit();

    try std.testing.expectEqual(@as(u16, 80), buf.width);
    try std.testing.expectEqual(@as(u16, 24), buf.height);
}

test "output buffer: set and get cell" {
    const allocator = std.testing.allocator;
    var buf = try OutputBuffer.init(allocator, 80, 24);
    defer buf.deinit();

    const cell = Cell{
        .char = 'A',
        .fg = .{ .standard = .red },
        .bg = .default,
        .attrs = .{},
    };

    buf.setCell(5, 10, cell);

    const retrieved = buf.getCell(5, 10).?;
    try std.testing.expectEqual('A', retrieved.char);
}

test "output buffer: write text" {
    const allocator = std.testing.allocator;
    var buf = try OutputBuffer.init(allocator, 80, 24);
    defer buf.deinit();

    buf.writeText(0, 0, "Hello", .default, .default, .{});

    try std.testing.expectEqual('H', buf.getCell(0, 0).?.char);
    try std.testing.expectEqual('e', buf.getCell(0, 1).?.char);
    try std.testing.expectEqual('l', buf.getCell(0, 2).?.char);
    try std.testing.expectEqual('l', buf.getCell(0, 3).?.char);
    try std.testing.expectEqual('o', buf.getCell(0, 4).?.char);
}

test "output buffer: damage tracking" {
    const allocator = std.testing.allocator;
    var buf = try OutputBuffer.init(allocator, 80, 24);
    defer buf.deinit();

    // Write to back buffer
    buf.writeText(5, 0, "Changed", .default, .default, .{});

    // Compute damage
    buf.computeDamage();

    // Line 5 should be dirty
    try std.testing.expect(buf.dirty_lines[5]);

    // Other lines should not be dirty
    try std.testing.expect(!buf.dirty_lines[0]);
    try std.testing.expect(!buf.dirty_lines[10]);
}
