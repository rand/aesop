//! Plugin system for extending editor functionality
//! Provides hooks, lifecycle management, and plugin discovery

const std = @import("std");

/// Plugin interface - all plugins must implement this
pub const Plugin = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    vtable: *const VTable,
    state: *anyopaque,

    pub const VTable = struct {
        init: *const fn (allocator: std.mem.Allocator) anyerror!*anyopaque,
        deinit: *const fn (state: *anyopaque) void,
        on_buffer_open: ?*const fn (state: *anyopaque, buffer_id: usize) anyerror!void = null,
        on_buffer_save: ?*const fn (state: *anyopaque, buffer_id: usize) anyerror!void = null,
        on_buffer_close: ?*const fn (state: *anyopaque, buffer_id: usize) anyerror!void = null,
        on_key_press: ?*const fn (state: *anyopaque, key: u21) anyerror!bool = null,
        on_mode_change: ?*const fn (state: *anyopaque, old_mode: u8, new_mode: u8) anyerror!void = null,
    };
};

/// Plugin manager - loads and manages plugins
pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(*Plugin),
    enabled: std.StringHashMap(bool),

    /// Initialize plugin manager
    pub fn init(allocator: std.mem.Allocator) PluginManager {
        return .{
            .allocator = allocator,
            .plugins = std.ArrayList(*Plugin).init(allocator),
            .enabled = std.StringHashMap(bool).init(allocator),
        };
    }

    /// Clean up plugin manager and all loaded plugins
    pub fn deinit(self: *PluginManager) void {
        // Deinitialize all plugins
        for (self.plugins.items) |plugin| {
            plugin.vtable.deinit(plugin.state);
            self.allocator.destroy(plugin);
        }

        self.plugins.deinit();
        self.enabled.deinit();
    }

    /// Register a plugin
    pub fn register(self: *PluginManager, plugin: *Plugin) !void {
        try self.plugins.append(plugin);
        try self.enabled.put(plugin.name, true);
    }

    /// Enable a plugin
    pub fn enable(self: *PluginManager, name: []const u8) !void {
        try self.enabled.put(name, true);
    }

    /// Disable a plugin
    pub fn disable(self: *PluginManager, name: []const u8) !void {
        try self.enabled.put(name, false);
    }

    /// Check if plugin is enabled
    pub fn isEnabled(self: *const PluginManager, name: []const u8) bool {
        return self.enabled.get(name) orelse false;
    }

    /// Get plugin by name
    pub fn getPlugin(self: *const PluginManager, name: []const u8) ?*Plugin {
        for (self.plugins.items) |plugin| {
            if (std.mem.eql(u8, plugin.name, name)) {
                return plugin;
            }
        }
        return null;
    }

    /// Get all registered plugins
    pub fn getPlugins(self: *const PluginManager) []const *Plugin {
        return self.plugins.items;
    }

    // === Hook Dispatchers ===

    /// Dispatch buffer open event to all enabled plugins
    pub fn dispatchBufferOpen(self: *const PluginManager, buffer_id: usize) !void {
        for (self.plugins.items) |plugin| {
            if (!self.isEnabled(plugin.name)) continue;
            if (plugin.vtable.on_buffer_open) |hook| {
                try hook(plugin.state, buffer_id);
            }
        }
    }

    /// Dispatch buffer save event to all enabled plugins
    pub fn dispatchBufferSave(self: *const PluginManager, buffer_id: usize) !void {
        for (self.plugins.items) |plugin| {
            if (!self.isEnabled(plugin.name)) continue;
            if (plugin.vtable.on_buffer_save) |hook| {
                try hook(plugin.state, buffer_id);
            }
        }
    }

    /// Dispatch buffer close event to all enabled plugins
    pub fn dispatchBufferClose(self: *const PluginManager, buffer_id: usize) !void {
        for (self.plugins.items) |plugin| {
            if (!self.isEnabled(plugin.name)) continue;
            if (plugin.vtable.on_buffer_close) |hook| {
                try hook(plugin.state, buffer_id);
            }
        }
    }

    /// Dispatch key press event to all enabled plugins
    /// Returns true if any plugin handled the key
    pub fn dispatchKeyPress(self: *const PluginManager, key: u21) !bool {
        for (self.plugins.items) |plugin| {
            if (!self.isEnabled(plugin.name)) continue;
            if (plugin.vtable.on_key_press) |hook| {
                const handled = try hook(plugin.state, key);
                if (handled) return true;
            }
        }
        return false;
    }

    /// Dispatch mode change event to all enabled plugins
    pub fn dispatchModeChange(self: *const PluginManager, old_mode: u8, new_mode: u8) !void {
        for (self.plugins.items) |plugin| {
            if (!self.isEnabled(plugin.name)) continue;
            if (plugin.vtable.on_mode_change) |hook| {
                try hook(plugin.state, old_mode, new_mode);
            }
        }
    }
};

// === Example Plugin Implementation ===

/// Example plugin that logs events
const LoggerPlugin = struct {
    message_count: usize,

    fn init(allocator: std.mem.Allocator) !*anyopaque {
        const self = try allocator.create(LoggerPlugin);
        self.* = .{ .message_count = 0 };
        return self;
    }

    fn deinit(state: *anyopaque) void {
        _ = state;
    }

    fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        self.message_count += 1;
        _ = buffer_id;
    }

    fn onBufferSave(state: *anyopaque, buffer_id: usize) !void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        self.message_count += 1;
        _ = buffer_id;
    }

    const vtable = Plugin.VTable{
        .init = init,
        .deinit = deinit,
        .on_buffer_open = onBufferOpen,
        .on_buffer_save = onBufferSave,
    };
};

// === Tests ===

test "plugin manager: init and deinit" {
    const allocator = std.testing.allocator;
    var manager = PluginManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(usize, 0), manager.plugins.items.len);
}

test "plugin manager: register plugin" {
    const allocator = std.testing.allocator;
    var manager = PluginManager.init(allocator);
    defer manager.deinit();

    const state = try LoggerPlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "logger",
        .version = "0.1.0",
        .description = "Example logger plugin",
        .vtable = &LoggerPlugin.vtable,
        .state = state,
    };

    try manager.register(plugin);

    try std.testing.expectEqual(@as(usize, 1), manager.plugins.items.len);
    try std.testing.expect(manager.isEnabled("logger"));
}

test "plugin manager: enable/disable" {
    const allocator = std.testing.allocator;
    var manager = PluginManager.init(allocator);
    defer manager.deinit();

    const state = try LoggerPlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "logger",
        .version = "0.1.0",
        .description = "Example logger plugin",
        .vtable = &LoggerPlugin.vtable,
        .state = state,
    };

    try manager.register(plugin);
    try std.testing.expect(manager.isEnabled("logger"));

    try manager.disable("logger");
    try std.testing.expect(!manager.isEnabled("logger"));

    try manager.enable("logger");
    try std.testing.expect(manager.isEnabled("logger"));
}

test "plugin manager: dispatch buffer events" {
    const allocator = std.testing.allocator;
    var manager = PluginManager.init(allocator);
    defer manager.deinit();

    const state = try LoggerPlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "logger",
        .version = "0.1.0",
        .description = "Example logger plugin",
        .vtable = &LoggerPlugin.vtable,
        .state = state,
    };

    try manager.register(plugin);

    // Dispatch events
    try manager.dispatchBufferOpen(1);
    try manager.dispatchBufferSave(1);

    // Verify plugin received events
    const logger_state: *LoggerPlugin = @ptrCast(@alignCast(plugin.state));
    try std.testing.expectEqual(@as(usize, 2), logger_state.message_count);
}

test "plugin manager: get plugin by name" {
    const allocator = std.testing.allocator;
    var manager = PluginManager.init(allocator);
    defer manager.deinit();

    const state = try LoggerPlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "logger",
        .version = "0.1.0",
        .description = "Example logger plugin",
        .vtable = &LoggerPlugin.vtable,
        .state = state,
    };

    try manager.register(plugin);

    const found = manager.getPlugin("logger");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("logger", found.?.name);

    const not_found = manager.getPlugin("nonexistent");
    try std.testing.expect(not_found == null);
}
