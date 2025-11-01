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
        var events = std.ArrayList(Event).init(allocator);
        defer events.deinit();

        for (input) |byte| {
            if (try self.parseByte(byte)) |event| {
                try events.append(event);
            }
        }

        return events.toOwnedSlice();
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
                // TODO: Implement mouse event parsing
                self.state = .normal;
                return null;
            },
        }
    }

    fn parseCsi(self: *Parser, seq: []const u8) !?Event {
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
