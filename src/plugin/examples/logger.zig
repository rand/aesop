//! Example plugin: Event logger
//! Logs all editor events to a file for debugging and analytics

const std = @import("std");
const Plugin = @import("../system.zig").Plugin;

/// Logger plugin state
pub const LoggerPlugin = struct {
    allocator: std.mem.Allocator,
    log_file: ?std.fs.File,
    log_path: []const u8,
    event_count: usize,
    enabled: bool,

    pub fn init(allocator: std.mem.Allocator) !*anyopaque {
        const log_path = try allocator.dupe(u8, "/tmp/aesop-events.log");
        const self = try allocator.create(LoggerPlugin);
        self.* = .{
            .allocator = allocator,
            .log_file = null,
            .log_path = log_path,
            .event_count = 0,
            .enabled = true,
        };

        // Open log file
        self.log_file = std.fs.cwd().createFile(log_path, .{ .truncate = false }) catch |err| {
            std.debug.print("Logger plugin: Failed to open log file: {}\n", .{err});
            return self;
        };

        // Write header
        if (self.log_file) |file| {
            const timestamp = std.time.timestamp();
            file.writer().print("=== Aesop Event Log (started at {}) ===\n", .{timestamp}) catch {};
        }

        return self;
    }

    pub fn deinit(state: *anyopaque) void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        if (self.log_file) |file| {
            file.close();
        }
        self.allocator.free(self.log_path);
        self.allocator.destroy(self);
    }

    fn logEvent(self: *LoggerPlugin, event_name: []const u8, details: []const u8) void {
        if (!self.enabled) return;
        const file = self.log_file orelse return;

        self.event_count += 1;
        const timestamp = std.time.milliTimestamp();

        file.writer().print("[{}ms] Event #{}: {} - {s}\n", .{
            timestamp,
            self.event_count,
            event_name,
            details,
        }) catch {};
    }

    pub fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        var buf: [256]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "buffer_id={}", .{buffer_id});
        self.logEvent("buffer_open", details);
    }

    pub fn onBufferSave(state: *anyopaque, buffer_id: usize) !void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        var buf: [256]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "buffer_id={}", .{buffer_id});
        self.logEvent("buffer_save", details);
    }

    pub fn onBufferClose(state: *anyopaque, buffer_id: usize) !void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        var buf: [256]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "buffer_id={}", .{buffer_id});
        self.logEvent("buffer_close", details);
    }

    pub fn onKeyPress(state: *anyopaque, key: u21) !bool {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        var buf: [256]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "key=U+{X:0>4}", .{key});
        self.logEvent("key_press", details);
        return false; // Don't consume the key
    }

    pub fn onModeChange(state: *anyopaque, old_mode: u8, new_mode: u8) !void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        var buf: [256]u8 = undefined;
        const details = try std.fmt.bufPrint(&buf, "old={} new={}", .{ old_mode, new_mode });
        self.logEvent("mode_change", details);
    }

    pub const vtable = Plugin.VTable{
        .init = init,
        .deinit = deinit,
        .on_buffer_open = onBufferOpen,
        .on_buffer_save = onBufferSave,
        .on_buffer_close = onBufferClose,
        .on_key_press = onKeyPress,
        .on_mode_change = onModeChange,
    };
};

/// Create a plugin instance
pub fn createPlugin(allocator: std.mem.Allocator) !*Plugin {
    const state = try LoggerPlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "logger",
        .version = "1.0.0",
        .description = "Logs all editor events to /tmp/aesop-events.log",
        .vtable = &LoggerPlugin.vtable,
        .state = state,
    };
    return plugin;
}

// === Tests ===

test "logger plugin: event counting" {
    const allocator = std.testing.allocator;
    const state = try LoggerPlugin.init(allocator);
    defer LoggerPlugin.deinit(state);

    const self: *LoggerPlugin = @ptrCast(@alignCast(state));

    try LoggerPlugin.onBufferOpen(state, 1);
    try std.testing.expectEqual(@as(usize, 1), self.event_count);

    try LoggerPlugin.onBufferSave(state, 1);
    try std.testing.expectEqual(@as(usize, 2), self.event_count);

    try LoggerPlugin.onBufferClose(state, 1);
    try std.testing.expectEqual(@as(usize, 3), self.event_count);
}
