//! Repeat last action system (like vim's dot command)
//! Records and replays the last editing action

const std = @import("std");
const Command = @import("command.zig");

/// Recordable action type
pub const Action = struct {
    command_name: []const u8,
    // Could be extended with parameters for more complex actions

    pub fn deinit(self: *Action, allocator: std.mem.Allocator) void {
        allocator.free(self.command_name);
    }
};

/// Repeat system for tracking and replaying actions
pub const RepeatSystem = struct {
    last_action: ?Action = null,
    allocator: std.mem.Allocator,
    recording: bool = false,

    pub fn init(allocator: std.mem.Allocator) RepeatSystem {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RepeatSystem) void {
        if (self.last_action) |*action| {
            action.deinit(self.allocator);
        }
    }

    /// Record an action for later repeat
    pub fn recordAction(self: *RepeatSystem, command_name: []const u8) !void {
        // Don't record if we're currently replaying
        if (self.recording) return;

        // Free previous action
        if (self.last_action) |*action| {
            action.deinit(self.allocator);
        }

        // Store new action
        const name_copy = try self.allocator.dupe(u8, command_name);
        self.last_action = Action{
            .command_name = name_copy,
        };
    }

    /// Get the last recorded action
    pub fn getLastAction(self: *const RepeatSystem) ?Action {
        return self.last_action;
    }

    /// Mark that we're currently replaying (to prevent recursive recording)
    pub fn startReplay(self: *RepeatSystem) void {
        self.recording = true;
    }

    /// Mark that replay is complete
    pub fn endReplay(self: *RepeatSystem) void {
        self.recording = false;
    }

    /// Check if an action should be recorded (some commands shouldn't be)
    pub fn shouldRecord(command_name: []const u8) bool {
        // Don't record navigation, mode changes, or the repeat command itself
        const non_recordable = [_][]const u8{
            "move_left",
            "move_right",
            "move_up",
            "move_down",
            "move_line_start",
            "move_line_end",
            "move_file_start",
            "move_file_end",
            "move_word_forward",
            "move_word_backward",
            "scroll_up",
            "scroll_down",
            "scroll_page_up",
            "scroll_page_down",
            "center_cursor",
            "enter_insert_mode",
            "enter_normal_mode",
            "enter_select_mode",
            "enter_command_mode",
            "repeat_last_action",
            "undo",
            "redo",
            "save_buffer",
            "quit",
        };

        for (non_recordable) |name| {
            if (std.mem.eql(u8, command_name, name)) {
                return false;
            }
        }

        return true;
    }
};

// === Tests ===

test "repeat: record and get action" {
    const allocator = std.testing.allocator;
    var repeat = RepeatSystem.init(allocator);
    defer repeat.deinit();

    try repeat.recordAction("delete_line");

    const action = repeat.getLastAction();
    try std.testing.expect(action != null);
    try std.testing.expect(std.mem.eql(u8, action.?.command_name, "delete_line"));
}

test "repeat: should record filtering" {
    try std.testing.expect(!RepeatSystem.shouldRecord("move_left"));
    try std.testing.expect(!RepeatSystem.shouldRecord("undo"));
    try std.testing.expect(RepeatSystem.shouldRecord("delete_line"));
    try std.testing.expect(RepeatSystem.shouldRecord("change_word"));
}
