//! Plugin loader and discovery system
//! Provides a registry for compile-time plugin registration

const std = @import("std");
const Plugin = @import("system.zig").Plugin;

/// Plugin factory function type
pub const PluginFactory = *const fn (allocator: std.mem.Allocator) anyerror!*Plugin;

/// Plugin registry entry
const PluginEntry = struct {
    name: []const u8,
    factory: PluginFactory,
};

/// Compile-time plugin registry
/// Plugins register themselves here at compile time
const registry = [_]PluginEntry{
    // Add plugin factories here at compile time
    // Example:
    // .{ .name = "autocomplete", .factory = @import("examples/autocomplete.zig").createPlugin },
    // .{ .name = "logger", .factory = @import("examples/logger.zig").createPlugin },
};

/// Load all registered plugins
pub fn loadAllPlugins(allocator: std.mem.Allocator, manager: anytype) !void {
    for (registry) |entry| {
        const plugin = try entry.factory(allocator);
        try manager.register(plugin);

        std.debug.print("[PluginLoader] Loaded plugin: {s}\n", .{entry.name});
    }
}

/// Get list of available plugins
pub fn listAvailablePlugins(allocator: std.mem.Allocator) ![]const []const u8 {
    var names = std.ArrayList([]const u8).empty;
    for (registry) |entry| {
        try names.append(allocator, entry.name);
    }
    return names.toOwnedSlice(allocator);
}

/// Load a specific plugin by name
pub fn loadPlugin(allocator: std.mem.Allocator, name: []const u8) !*Plugin {
    for (registry) |entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return try entry.factory(allocator);
        }
    }
    return error.PluginNotFound;
}

/// Check if a plugin is available
pub fn hasPlugin(name: []const u8) bool {
    for (registry) |entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return true;
        }
    }
    return false;
}

// === Tests ===

test "loader: empty registry" {
    const allocator = std.testing.allocator;

    const names = try listAvailablePlugins(allocator);
    defer allocator.free(names);

    try std.testing.expectEqual(@as(usize, 0), names.len);
}

test "loader: hasPlugin" {
    try std.testing.expect(!hasPlugin("nonexistent"));
}
