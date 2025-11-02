//! Example plugin: Auto-complete pairs (brackets, quotes)
//! Demonstrates on_key_press hook and buffer manipulation

const std = @import("std");
const Plugin = @import("../system.zig").Plugin;

/// Autocomplete plugin state
pub const AutocompletePlugin = struct {
    allocator: std.mem.Allocator,
    enabled: bool,
    pair_count: usize,

    const pairs = .{
        .{ '(', ')' },
        .{ '[', ']' },
        .{ '{', '}' },
        .{ '"', '"' },
        .{ '\'', '\'' },
    };

    pub fn init(allocator: std.mem.Allocator) !*anyopaque {
        const self = try allocator.create(AutocompletePlugin);
        self.* = .{
            .allocator = allocator,
            .enabled = true,
            .pair_count = 0,
        };
        return self;
    }

    pub fn deinit(state: *anyopaque) void {
        const self: *AutocompletePlugin = @ptrCast(@alignCast(state));
        self.allocator.destroy(self);
    }

    pub fn onKeyPress(state: *anyopaque, key: u21) !bool {
        const self: *AutocompletePlugin = @ptrCast(@alignCast(state));
        if (!self.enabled) return false;

        // Check if key matches opening character of any pair
        inline for (pairs) |pair| {
            if (key == pair[0]) {
                self.pair_count += 1;
                // In a real implementation, we would insert the closing character
                // and move the cursor between them. This example just tracks pairs.
                return true; // Indicate we handled the key
            }
        }

        return false; // Let editor handle the key normally
    }

    pub fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
        const self: *AutocompletePlugin = @ptrCast(@alignCast(state));
        _ = self;
        _ = buffer_id;
        // Reset state for new buffer
    }

    pub const vtable = Plugin.VTable{
        .init = init,
        .deinit = deinit,
        .on_key_press = onKeyPress,
        .on_buffer_open = onBufferOpen,
    };
};

/// Create a plugin instance
pub fn createPlugin(allocator: std.mem.Allocator) !*Plugin {
    const state = try AutocompletePlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "autocomplete",
        .version = "1.0.0",
        .description = "Auto-complete brackets, quotes, and pairs",
        .vtable = &AutocompletePlugin.vtable,
        .state = state,
    };
    return plugin;
}

// === Tests ===

test "autocomplete plugin: pair tracking" {
    const allocator = std.testing.allocator;
    const state = try AutocompletePlugin.init(allocator);
    defer AutocompletePlugin.deinit(state);

    const self: *AutocompletePlugin = @ptrCast(@alignCast(state));

    // Opening bracket should be handled
    const handled = try AutocompletePlugin.onKeyPress(state, '(');
    try std.testing.expect(handled);
    try std.testing.expectEqual(@as(usize, 1), self.pair_count);

    // Regular character should not be handled
    const not_handled = try AutocompletePlugin.onKeyPress(state, 'a');
    try std.testing.expect(!not_handled);
}
