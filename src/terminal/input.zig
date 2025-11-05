//! Terminal input event parsing
//! Handles keyboard, mouse, and terminal resize events

const std = @import("std");

/// Key modifiers
pub const Modifiers = packed struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    meta: bool = false,

    pub fn none() Modifiers {
        return .{};
    }
};

/// Special keys
pub const Key = enum {
    // Navigation
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,

    // Editing
    backspace,
    delete,
    insert,
    tab,
    enter,
    escape,

    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
};

/// Input events
pub const Event = union(enum) {
    /// Character input (unicode codepoint)
    char: struct {
        codepoint: u21,
        mods: Modifiers,
    },

    /// Special key press
    key: struct {
        key: Key,
        mods: Modifiers,
    },

    /// Mouse event
    mouse: struct {
        kind: MouseKind,
        row: u16,
        col: u16,
        mods: Modifiers,
    },

    /// Terminal resize
    resize: struct {
        width: u16,
        height: u16,
    },

    /// Paste event (bracketed paste)
    paste: struct {
        text: []const u8,
    },
};

/// Mouse event types
pub const MouseKind = enum {
    press_left,
    press_middle,
    press_right,
    release,
    move,
    scroll_up,
    scroll_down,
};

/// Input parser state machine
pub const Parser = struct {
    buf: [256]u8 = undefined,
    pos: usize = 0,
    state: State = .normal,

    const State = enum {
        normal,
        escape,
        csi,
        mouse,
    };

    /// Parse incoming bytes and produce events
    pub fn parse(self: *Parser, allocator: std.mem.Allocator, input: []const u8) ![]Event {
        var events: std.ArrayList(Event) = .empty;
        defer events.deinit(allocator);

        for (input) |byte| {
            if (try self.parseByte(byte)) |event| {
                try events.append(allocator, event);
            }
        }

        // If we're still in escape state after processing all bytes,
        // treat it as a standalone Escape key (not part of an escape sequence)
        if (self.state == .escape) {
            self.state = .normal;
            try events.append(allocator, Event{ .key = .{ .key = .escape, .mods = Modifiers.none() } });
        }

        return events.toOwnedSlice(allocator);
    }

    fn parseByte(self: *Parser, byte: u8) !?Event {
        switch (self.state) {
            .normal => {
                if (byte == 0x1b) { // ESC
                    self.state = .escape;
                    self.pos = 0;
                    return null;
                } else if (byte == 0x7f) { // DEL -> Backspace
                    return Event{ .key = .{ .key = .backspace, .mods = Modifiers.none() } };
                } else if (byte == '\r' or byte == '\n') {
                    return Event{ .key = .{ .key = .enter, .mods = Modifiers.none() } };
                } else if (byte == '\t') {
                    return Event{ .key = .{ .key = .tab, .mods = Modifiers.none() } };
                } else if (byte >= 0x20 and byte < 0x7f) { // Printable ASCII
                    return Event{ .char = .{ .codepoint = byte, .mods = Modifiers.none() } };
                } else if (byte >= 0x01 and byte <= 0x1a) { // Ctrl+A through Ctrl+Z
                    const char = byte + 0x60; // Convert to lowercase letter
                    return Event{ .char = .{ .codepoint = char, .mods = .{ .ctrl = true } } };
                }
                return null;
            },

            .escape => {
                if (byte == '[') {
                    self.state = .csi;
                    self.pos = 0;
                    return null;
                } else {
                    // Alt + key
                    self.state = .normal;
                    if (byte >= 0x20 and byte < 0x7f) {
                        return Event{ .char = .{ .codepoint = byte, .mods = .{ .alt = true } } };
                    }
                    return null;
                }
            },

            .csi => {
                if (self.pos < self.buf.len) {
                    self.buf[self.pos] = byte;
                    self.pos += 1;
                }

                // Check for SGR mouse tracking (ESC[<...)
                if (self.pos == 1 and byte == '<') {
                    std.debug.print("DEBUG: Detected mouse SGR sequence start\n", .{});
                    self.state = .mouse;
                    self.pos = 0;
                    return null;
                }

                // Check for sequence terminator
                if (byte >= 0x40 and byte <= 0x7e) {
                    const seq = self.buf[0..self.pos];
                    self.state = .normal;
                    return try self.parseCsi(seq);
                }
                return null;
            },

            .mouse => {
                // Mouse tracking parsing (SGR mode)
                // Accumulate bytes until we hit M or m (press/release)
                if (self.pos < self.buf.len) {
                    self.buf[self.pos] = byte;
                    self.pos += 1;
                }

                // Check for sequence terminator (M=press, m=release)
                if (byte == 'M' or byte == 'm') {
                    const seq = self.buf[0..self.pos];
                    std.debug.print("DEBUG: Mouse sequence complete: {s}{c}\n", .{ seq, byte });
                    self.state = .normal;
                    const event = try self.parseMouseSgr(seq, byte == 'M');
                    if (event) |e| {
                        std.debug.print("DEBUG: Parsed event: {}\n", .{e});
                    } else {
                        std.debug.print("DEBUG: parseMouseSgr returned null\n", .{});
                    }
                    return event;
                }
                return null;
            },
        }
    }

    fn parseCsi(_: *Parser, seq: []const u8) !?Event {
        if (seq.len == 0) return null;

        // Arrow keys
        if (seq.len == 1) {
            return switch (seq[0]) {
                'A' => Event{ .key = .{ .key = .up, .mods = Modifiers.none() } },
                'B' => Event{ .key = .{ .key = .down, .mods = Modifiers.none() } },
                'C' => Event{ .key = .{ .key = .right, .mods = Modifiers.none() } },
                'D' => Event{ .key = .{ .key = .left, .mods = Modifiers.none() } },
                'H' => Event{ .key = .{ .key = .home, .mods = Modifiers.none() } },
                'F' => Event{ .key = .{ .key = .end, .mods = Modifiers.none() } },
                else => null,
            };
        }

        // Function keys and other special sequences
        if (seq[seq.len - 1] == '~') {
            const num_end = seq.len - 1;
            const num_str = seq[0..num_end];
            const num = std.fmt.parseInt(u8, num_str, 10) catch return null;

            return switch (num) {
                1 => Event{ .key = .{ .key = .home, .mods = Modifiers.none() } },
                2 => Event{ .key = .{ .key = .insert, .mods = Modifiers.none() } },
                3 => Event{ .key = .{ .key = .delete, .mods = Modifiers.none() } },
                4 => Event{ .key = .{ .key = .end, .mods = Modifiers.none() } },
                5 => Event{ .key = .{ .key = .page_up, .mods = Modifiers.none() } },
                6 => Event{ .key = .{ .key = .page_down, .mods = Modifiers.none() } },
                11 => Event{ .key = .{ .key = .f1, .mods = Modifiers.none() } },
                12 => Event{ .key = .{ .key = .f2, .mods = Modifiers.none() } },
                13 => Event{ .key = .{ .key = .f3, .mods = Modifiers.none() } },
                14 => Event{ .key = .{ .key = .f4, .mods = Modifiers.none() } },
                15 => Event{ .key = .{ .key = .f5, .mods = Modifiers.none() } },
                17 => Event{ .key = .{ .key = .f6, .mods = Modifiers.none() } },
                18 => Event{ .key = .{ .key = .f7, .mods = Modifiers.none() } },
                19 => Event{ .key = .{ .key = .f8, .mods = Modifiers.none() } },
                20 => Event{ .key = .{ .key = .f9, .mods = Modifiers.none() } },
                21 => Event{ .key = .{ .key = .f10, .mods = Modifiers.none() } },
                23 => Event{ .key = .{ .key = .f11, .mods = Modifiers.none() } },
                24 => Event{ .key = .{ .key = .f12, .mods = Modifiers.none() } },
                else => null,
            };
        }

        return null;
    }

    fn parseMouseSgr(_: *Parser, seq: []const u8, is_press: bool) !?Event {
        // SGR mouse format: ESC[<button;col;rowM (press) or ...m (release)
        // Example: ESC[<0;5;10M means left button press at col=5, row=10
        // Example: ESC[<0;5;10m means button release at col=5, row=10
        // Example: ESC[<64;5;10M means scroll up at col=5, row=10
        // Example: ESC[<65;5;10M means scroll down at col=5, row=10

        if (seq.len == 0) return null;

        // Parse button;col;row
        var parts: [3]u16 = undefined;
        var part_idx: usize = 0;
        var num_start: usize = 0;

        for (seq, 0..) |byte, i| {
            if (byte == ';' or i == seq.len - 1) {
                const num_end = if (i == seq.len - 1) seq.len else i;
                const num_str = seq[num_start..num_end];
                if (num_str.len > 0 and (byte != 'M' and byte != 'm')) {
                    parts[part_idx] = std.fmt.parseInt(u16, num_str, 10) catch return null;
                    part_idx += 1;
                    if (part_idx >= 3) break;
                }
                num_start = i + 1;
            }
        }

        if (part_idx != 3) return null;

        const button = parts[0];
        const col = parts[1];
        const row = parts[2];

        // Decode button and modifiers
        const button_base = button & 0x3; // Lower 2 bits are button
        const modifiers_bits = button & 0x1c; // Bits 2-4 are modifiers
        const scroll_bits = button & 0x40; // Bit 6 indicates scroll

        // Build modifiers
        var mods = Modifiers{};
        if (modifiers_bits & 0x04 != 0) mods.shift = true;
        if (modifiers_bits & 0x08 != 0) mods.alt = true;
        if (modifiers_bits & 0x10 != 0) mods.ctrl = true;

        // Determine mouse kind
        const kind: MouseKind = if (scroll_bits != 0) blk: {
            // Scroll events
            if (button_base == 0) {
                break :blk .scroll_up;
            } else {
                break :blk .scroll_down;
            }
        } else if (!is_press) blk: {
            // Release event
            break :blk .release;
        } else switch (button_base) {
            0 => .press_left,
            1 => .press_middle,
            2 => .press_right,
            3 => .move, // Motion events when button is held
            else => return null,
        };

        return Event{ .mouse = .{
            .kind = kind,
            .row = row,
            .col = col,
            .mods = mods,
        } };
    }
};

test "parse simple character" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    const events = try parser.parse(allocator, "a");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.char, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(@as(u21, 'a'), events[0].char.codepoint);
}

test "parse arrow key" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    const events = try parser.parse(allocator, "\x1b[A");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.key, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(Key.up, events[0].key.key);
}

test "parse ctrl+key" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    const events = try parser.parse(allocator, "\x01"); // Ctrl+A
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.char, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(@as(u21, 'a'), events[0].char.codepoint);
    try std.testing.expect(events[0].char.mods.ctrl);
}

test "parse mouse left button press" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    // ESC[<0;10;5M means left button press at col=10, row=5
    const events = try parser.parse(allocator, "\x1b[<0;10;5M");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.mouse, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(MouseKind.press_left, events[0].mouse.kind);
    try std.testing.expectEqual(@as(u16, 10), events[0].mouse.col);
    try std.testing.expectEqual(@as(u16, 5), events[0].mouse.row);
}

test "parse mouse button release" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    // ESC[<0;10;5m (lowercase m) means button release
    const events = try parser.parse(allocator, "\x1b[<0;10;5m");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.mouse, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(MouseKind.release, events[0].mouse.kind);
    try std.testing.expectEqual(@as(u16, 10), events[0].mouse.col);
    try std.testing.expectEqual(@as(u16, 5), events[0].mouse.row);
}

test "parse mouse scroll up" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    // ESC[<64;10;5M means scroll up at col=10, row=5
    const events = try parser.parse(allocator, "\x1b[<64;10;5M");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.mouse, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(MouseKind.scroll_up, events[0].mouse.kind);
    try std.testing.expectEqual(@as(u16, 10), events[0].mouse.col);
    try std.testing.expectEqual(@as(u16, 5), events[0].mouse.row);
}

test "parse mouse scroll down" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    // ESC[<65;10;5M means scroll down at col=10, row=5
    const events = try parser.parse(allocator, "\x1b[<65;10;5M");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.mouse, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(MouseKind.scroll_down, events[0].mouse.kind);
    try std.testing.expectEqual(@as(u16, 10), events[0].mouse.col);
    try std.testing.expectEqual(@as(u16, 5), events[0].mouse.row);
}

test "parse mouse with shift modifier" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    // ESC[<4;10;5M means left button (0) + shift (bit 2 = 4)
    const events = try parser.parse(allocator, "\x1b[<4;10;5M");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.mouse, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(MouseKind.press_left, events[0].mouse.kind);
    try std.testing.expect(events[0].mouse.mods.shift);
    try std.testing.expectEqual(@as(u16, 10), events[0].mouse.col);
    try std.testing.expectEqual(@as(u16, 5), events[0].mouse.row);
}

test "parse mouse middle button" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    // ESC[<1;10;5M means middle button press
    const events = try parser.parse(allocator, "\x1b[<1;10;5M");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.mouse, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(MouseKind.press_middle, events[0].mouse.kind);
}

test "parse mouse right button" {
    var parser = Parser{};
    const allocator = std.testing.allocator;

    // ESC[<2;10;5M means right button press
    const events = try parser.parse(allocator, "\x1b[<2;10;5M");
    defer allocator.free(events);

    try std.testing.expectEqual(@as(usize, 1), events.len);
    try std.testing.expectEqual(Event.mouse, std.meta.activeTag(events[0]));
    try std.testing.expectEqual(MouseKind.press_right, events[0].mouse.kind);
}
