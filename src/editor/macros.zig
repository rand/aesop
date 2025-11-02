//! Macro recording and playback system
//! Records command sequences and stores them in registers

const std = @import("std");
const Registers = @import("registers.zig");

/// Recorded command in a macro
pub const RecordedCommand = struct {
    name: []const u8,
    timestamp: i64,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !RecordedCommand {
        return .{
            .name = try allocator.dupe(u8, name),
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *RecordedCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// Macro recorder state
pub const MacroRecorder = struct {
    recording: bool = false,
    target_register: ?u8 = null,
    commands: std.ArrayList(RecordedCommand),
    allocator: std.mem.Allocator,
    playback_count: usize = 1,

    pub fn init(allocator: std.mem.Allocator) MacroRecorder {
        return .{
            .allocator = allocator,
            .commands = std.ArrayList(RecordedCommand).empty,
        };
    }

    pub fn deinit(self: *MacroRecorder) void {
        for (self.commands.items) |*cmd| {
            cmd.deinit(self.allocator);
        }
        self.commands.deinit(self.allocator);
    }

    /// Start recording to a register
    pub fn startRecording(self: *MacroRecorder, register: u8) !void {
        if (self.recording) {
            return error.AlreadyRecording;
        }

        // Validate register (a-z)
        if (register < 'a' or register > 'z') {
            return error.InvalidRegister;
        }

        // Clear previous recording
        for (self.commands.items) |*cmd| {
            cmd.deinit(self.allocator);
        }
        self.commands.clearRetainingCapacity();

        self.recording = true;
        self.target_register = register;
    }

    /// Stop recording and save to register
    pub fn stopRecording(self: *MacroRecorder, registers: *Registers.RegisterManager) !void {
        if (!self.recording) {
            return error.NotRecording;
        }

        const register = self.target_register.?;

        // Serialize commands to string format
        const macro_text = try self.serializeCommands();
        defer self.allocator.free(macro_text);

        // Store in register as text
        const register_id = Registers.RegisterId{ .named = register };
        try registers.set(register_id, macro_text, false);

        self.recording = false;
        self.target_register = null;

        // Clear commands after saving
        for (self.commands.items) |*cmd| {
            cmd.deinit(self.allocator);
        }
        self.commands.clearRetainingCapacity();
    }

    /// Record a command
    pub fn recordCommand(self: *MacroRecorder, command_name: []const u8) !void {
        if (!self.recording) return;

        // Don't record the macro recording commands themselves
        if (std.mem.eql(u8, command_name, "start_macro_recording")) return;
        if (std.mem.eql(u8, command_name, "stop_macro_recording")) return;
        if (std.mem.eql(u8, command_name, "play_macro")) return;

        const cmd = try RecordedCommand.init(self.allocator, command_name);
        try self.commands.append(self.allocator, cmd);
    }

    /// Serialize commands to string format (one command per line)
    fn serializeCommands(self: *const MacroRecorder) ![]const u8 {
        if (self.commands.items.len == 0) {
            return try self.allocator.dupe(u8, "");
        }

        var result = std.ArrayList(u8).empty;
        defer result.deinit(self.allocator);

        for (self.commands.items, 0..) |cmd, i| {
            try result.appendSlice(self.allocator, cmd.name);
            if (i < self.commands.items.len - 1) {
                try result.append(self.allocator, '\n');
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Deserialize commands from string format
    pub fn deserializeCommands(self: *MacroRecorder, text: []const u8) !void {
        // Clear existing commands
        for (self.commands.items) |*cmd| {
            cmd.deinit(self.allocator);
        }
        self.commands.clearRetainingCapacity();

        if (text.len == 0) return;

        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const cmd = try RecordedCommand.init(self.allocator, line);
            try self.commands.append(self.allocator, cmd);
        }
    }

    /// Get commands for playback
    pub fn getCommands(self: *const MacroRecorder) []const RecordedCommand {
        return self.commands.items;
    }

    /// Check if currently recording
    pub fn isRecording(self: *const MacroRecorder) bool {
        return self.recording;
    }

    /// Get current recording register
    pub fn getRecordingRegister(self: *const MacroRecorder) ?u8 {
        return self.target_register;
    }

    /// Set playback count for next macro execution
    pub fn setPlaybackCount(self: *MacroRecorder, count: usize) void {
        self.playback_count = if (count > 0) count else 1;
    }

    /// Get and reset playback count
    pub fn consumePlaybackCount(self: *MacroRecorder) usize {
        const count = self.playback_count;
        self.playback_count = 1;
        return count;
    }
};

// === Tests ===

test "macro: start and stop recording" {
    const allocator = std.testing.allocator;
    var recorder = MacroRecorder.init(allocator);
    defer recorder.deinit();

    var registers = Registers.RegisterManager.init(allocator);
    defer registers.deinit();

    // Start recording to register 'a'
    try recorder.startRecording('a');
    try std.testing.expect(recorder.isRecording());
    try std.testing.expectEqual(@as(?u8, 'a'), recorder.getRecordingRegister());

    // Record some commands
    try recorder.recordCommand("move_right");
    try recorder.recordCommand("insert_mode");

    // Stop recording
    try recorder.stopRecording(&registers);
    try std.testing.expect(!recorder.isRecording());

    // Check register contains macro
    const reg_id = Registers.RegisterId{ .named = 'a' };
    const content = registers.get(reg_id);
    try std.testing.expect(content != null);
    try std.testing.expect(content.?.text.len > 0);
}

test "macro: record and deserialize" {
    const allocator = std.testing.allocator;
    var recorder = MacroRecorder.init(allocator);
    defer recorder.deinit();

    var registers = Registers.RegisterManager.init(allocator);
    defer registers.deinit();

    // Record macro
    try recorder.startRecording('b');
    try recorder.recordCommand("move_word_forward");
    try recorder.recordCommand("delete_word");
    try recorder.stopRecording(&registers);

    // Deserialize from register
    const reg_id = Registers.RegisterId{ .named = 'b' };
    const content = registers.get(reg_id);
    try std.testing.expect(content != null);

    try recorder.deserializeCommands(content.?.text);
    const commands = recorder.getCommands();
    try std.testing.expectEqual(@as(usize, 2), commands.len);
    try std.testing.expect(std.mem.eql(u8, commands[0].name, "move_word_forward"));
    try std.testing.expect(std.mem.eql(u8, commands[1].name, "delete_word"));
}

test "macro: playback count" {
    const allocator = std.testing.allocator;
    var recorder = MacroRecorder.init(allocator);
    defer recorder.deinit();

    recorder.setPlaybackCount(5);
    try std.testing.expectEqual(@as(usize, 5), recorder.consumePlaybackCount());
    try std.testing.expectEqual(@as(usize, 1), recorder.consumePlaybackCount()); // Reset to 1
}

test "macro: invalid register" {
    const allocator = std.testing.allocator;
    var recorder = MacroRecorder.init(allocator);
    defer recorder.deinit();

    // Try invalid register
    const result = recorder.startRecording('1');
    try std.testing.expectError(error.InvalidRegister, result);
}

test "macro: don't record macro commands" {
    const allocator = std.testing.allocator;
    var recorder = MacroRecorder.init(allocator);
    defer recorder.deinit();

    try recorder.startRecording('c');
    try recorder.recordCommand("move_right");
    try recorder.recordCommand("start_macro_recording"); // Should be ignored
    try recorder.recordCommand("insert_mode");

    const commands = recorder.getCommands();
    try std.testing.expectEqual(@as(usize, 2), commands.len);
    try std.testing.expect(std.mem.eql(u8, commands[0].name, "move_right"));
    try std.testing.expect(std.mem.eql(u8, commands[1].name, "insert_mode"));
}
