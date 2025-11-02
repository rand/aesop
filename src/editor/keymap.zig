//! Keymap system for modal editing
//! Maps key sequences to commands based on current mode

const std = @import("std");
const Mode = @import("mode.zig").Mode;
const input = @import("../terminal/input.zig");

/// Key representation
pub const Key = union(enum) {
    char: u21,              // Regular character
    special: input.Key,     // Special key (arrow, enter, etc.)

    pub fn eql(self: Key, other: Key) bool {
        return switch (self) {
            .char => |c| other == .char and c == other.char,
            .special => |s| other == .special and s == other.special,
        };
    }

    pub fn format(
        self: Key,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .char => |c| {
                if (c >= 32 and c < 127) {
                    try writer.print("{c}", .{@as(u8, @intCast(c))});
                } else {
                    try writer.print("U+{X}", .{c});
                }
            },
            .special => |s| try writer.print("<{s}>", .{@tagName(s)}),
        }
    }
};

/// Key sequence (for chords like "g g")
pub const KeySequence = struct {
    keys: [4]Key = undefined,
    len: usize = 0,

    pub fn append(self: *KeySequence, key: Key) !void {
        if (self.len >= self.keys.len) return error.SequenceFull;
        self.keys[self.len] = key;
        self.len += 1;
    }

    pub fn constSlice(self: *const KeySequence) []const Key {
        return self.keys[0..self.len];
    }
};

/// Key binding - maps key sequence to command
pub const Binding = struct {
    keys: KeySequence,
    command: []const u8,
    description: ?[]const u8 = null,

    pub fn fromSingleKey(key: Key, command: []const u8) Binding {
        var keys: KeySequence = .{};
        keys.append(key) catch unreachable;

        return .{
            .keys = keys,
            .command = command,
        };
    }

    pub fn fromChord(key1: Key, key2: Key, command: []const u8) Binding {
        var keys: KeySequence = .{};
        keys.append(key1) catch unreachable;
        keys.append(key2) catch unreachable;

        return .{
            .keys = keys,
            .command = command,
        };
    }

    pub fn matchesSequence(self: *const Binding, seq: []const Key) bool {
        const binding_keys = self.keys.constSlice();
        if (binding_keys.len != seq.len) return false;

        for (binding_keys, seq) |bk, sk| {
            if (!bk.eql(sk)) return false;
        }

        return true;
    }
};

/// Keymap for a specific mode
pub const Keymap = struct {
    mode: Mode,
    bindings: std.ArrayList(Binding),
    allocator: std.mem.Allocator,

    /// Initialize keymap for mode
    pub fn init(allocator: std.mem.Allocator, mode: Mode) Keymap {
        return .{
            .mode = mode,
            .bindings = std.ArrayList(Binding).empty,
            .allocator = allocator,
        };
    }

    /// Clean up keymap
    pub fn deinit(self: *Keymap) void {
        self.bindings.deinit(self.allocator);
    }

    /// Add a binding
    pub fn bind(self: *Keymap, binding: Binding) !void {
        try self.bindings.append(self.allocator, binding);
    }

    /// Find command for key sequence
    pub fn lookup(self: *const Keymap, keys: []const Key) ?[]const u8 {
        for (self.bindings.items) |*binding| {
            if (binding.matchesSequence(keys)) {
                return binding.command;
            }
        }
        return null;
    }

    /// Get all bindings
    pub fn getBindings(self: *const Keymap) []const Binding {
        return self.bindings.items;
    }
};

/// Keymap manager - manages keymaps for all modes
pub const KeymapManager = struct {
    keymaps: std.EnumArray(Mode, Keymap),
    pending_keys: KeySequence,
    allocator: std.mem.Allocator,

    /// Initialize keymap manager
    pub fn init(allocator: std.mem.Allocator) KeymapManager {
        var manager = KeymapManager{
            .keymaps = undefined,
            .pending_keys = .{},
            .allocator = allocator,
        };

        // Initialize keymaps for each mode
        inline for (std.meta.fields(Mode)) |field| {
            const mode: Mode = @enumFromInt(field.value);
            manager.keymaps.set(mode, Keymap.init(allocator, mode));
        }

        return manager;
    }

    /// Clean up all keymaps
    pub fn deinit(self: *KeymapManager) void {
        var iter = self.keymaps.iterator();
        while (iter.next()) |entry| {
            entry.value.deinit();
        }
    }

    /// Get keymap for mode
    pub fn getKeymap(self: *KeymapManager, mode: Mode) *Keymap {
        return self.keymaps.getPtr(mode);
    }

    /// Add binding to mode
    pub fn bind(self: *KeymapManager, mode: Mode, binding: Binding) !void {
        try self.getKeymap(mode).bind(binding);
    }

    /// Process key input and return command if sequence matched
    pub fn processKey(self: *KeymapManager, mode: Mode, key: Key) !?[]const u8 {
        // Add key to pending sequence
        try self.pending_keys.append(key);

        // Try to match against bindings
        const keymap = self.getKeymap(mode);
        const pending = self.pending_keys.constSlice();

        if (keymap.lookup(pending)) |command| {
            // Found exact match - clear pending and return command
            self.pending_keys.len = 0;
            return command;
        }

        // Check if any binding starts with this sequence (potential chord)
        var has_potential = false;
        for (keymap.getBindings()) |binding| {
            const binding_keys = binding.keys.constSlice();
            if (binding_keys.len > pending.len) {
                // Check if binding starts with pending sequence
                var matches = true;
                for (pending, 0..) |pk, i| {
                    if (!pk.eql(binding_keys[i])) {
                        matches = false;
                        break;
                    }
                }
                if (matches) {
                    has_potential = true;
                    break;
                }
            }
        }

        if (!has_potential) {
            // No potential matches - clear pending
            self.pending_keys.len = 0;
            return null;
        }

        // Still waiting for more keys in chord
        return null;
    }

    /// Clear pending key sequence
    pub fn clearPending(self: *KeymapManager) void {
        self.pending_keys.len = 0;
    }

    /// Check if there are pending keys
    pub fn hasPending(self: *const KeymapManager) bool {
        return self.pending_keys.len > 0;
    }
};

/// Setup default keymaps
pub fn setupDefaults(manager: *KeymapManager) !void {
    // Normal mode bindings
    const normal_map = manager.getKeymap(.normal);

    // Motion: hjkl
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'h' }, "move_left"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'j' }, "move_down"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'k' }, "move_up"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'l' }, "move_right"));

    // Motion: word movements
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'w' }, "move_word_forward"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'b' }, "move_word_backward"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'e' }, "move_word_end"));

    // Motion: line start/end
    try normal_map.bind(Binding.fromSingleKey(.{ .char = '0' }, "move_line_start"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = '$' }, "move_line_end"));

    // Motion: file start/end (gg/G)
    try normal_map.bind(Binding.fromChord(.{ .char = 'g' }, .{ .char = 'g' }, "move_file_start"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'G' }, "move_file_end"));

    // Insert mode
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'i' }, "insert_mode"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'a' }, "insert_after"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'I' }, "insert_line_start"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'A' }, "insert_line_end"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'o' }, "open_below"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'O' }, "open_above"));

    // Select mode
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'v' }, "select_mode"));

    // Deletion
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'x' }, "delete_char"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'X' }, "delete_char_before"));
    try normal_map.bind(Binding.fromChord(.{ .char = 'd' }, .{ .char = 'd' }, "delete_line"));
    try normal_map.bind(Binding.fromChord(.{ .char = 'd' }, .{ .char = 'w' }, "delete_word"));

    // Undo/redo
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'u' }, "undo"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'U' }, "redo"));

    // Clipboard (yank/paste)
    try normal_map.bind(Binding.fromChord(.{ .char = 'y' }, .{ .char = 'y' }, "yank_line"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'p' }, "paste_after"));
    try normal_map.bind(Binding.fromSingleKey(.{ .char = 'P' }, "paste_before"));

    // Insert mode bindings
    const insert_map = manager.getKeymap(.insert);
    try insert_map.bind(Binding.fromSingleKey(.{ .special = .escape }, "normal_mode"));

    // Select mode bindings
    const select_map = manager.getKeymap(.select);
    try select_map.bind(Binding.fromSingleKey(.{ .special = .escape }, "normal_mode"));
}

test "keymap: bind and lookup" {
    const allocator = std.testing.allocator;
    var keymap = Keymap.init(allocator, .normal);
    defer keymap.deinit();

    const binding = Binding.fromSingleKey(.{ .char = 'h' }, "move_left");
    try keymap.bind(binding);

    const keys = [_]Key{.{ .char = 'h' }};
    const command = keymap.lookup(&keys);

    try std.testing.expect(command != null);
    try std.testing.expectEqualStrings("move_left", command.?);
}

test "keymap: chord lookup" {
    const allocator = std.testing.allocator;
    var keymap = Keymap.init(allocator, .normal);
    defer keymap.deinit();

    const binding = Binding.fromChord(.{ .char = 'g' }, .{ .char = 'g' }, "move_file_start");
    try keymap.bind(binding);

    const keys = [_]Key{ .{ .char = 'g' }, .{ .char = 'g' } };
    const command = keymap.lookup(&keys);

    try std.testing.expect(command != null);
    try std.testing.expectEqualStrings("move_file_start", command.?);
}

test "keymap manager: process single key" {
    const allocator = std.testing.allocator;
    var manager = KeymapManager.init(allocator);
    defer manager.deinit();

    try setupDefaults(&manager);

    const command = try manager.processKey(.normal, .{ .char = 'h' });
    try std.testing.expect(command != null);
    try std.testing.expectEqualStrings("move_left", command.?);
}

test "keymap manager: process chord" {
    const allocator = std.testing.allocator;
    var manager = KeymapManager.init(allocator);
    defer manager.deinit();

    try setupDefaults(&manager);

    // First 'g' - should wait for more keys
    const first = try manager.processKey(.normal, .{ .char = 'g' });
    try std.testing.expect(first == null);
    try std.testing.expect(manager.hasPending());

    // Second 'g' - should match command
    const second = try manager.processKey(.normal, .{ .char = 'g' });
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings("move_file_start", second.?);
    try std.testing.expect(!manager.hasPending());
}
