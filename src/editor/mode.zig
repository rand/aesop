//! Modal editing system
//! Manages editor modes (normal, insert, select, command) and transitions

const std = @import("std");

/// Editor modes
pub const Mode = enum {
    normal,
    insert,
    select,
    command,

    /// Get human-readable name
    pub fn name(self: Mode) []const u8 {
        return switch (self) {
            .normal => "NORMAL",
            .insert => "INSERT",
            .select => "SELECT",
            .command => "COMMAND",
        };
    }

    /// Get short name for status line
    pub fn shortName(self: Mode) []const u8 {
        return switch (self) {
            .normal => "N",
            .insert => "I",
            .select => "S",
            .command => "C",
        };
    }

    /// Check if mode accepts text input
    pub fn acceptsTextInput(self: Mode) bool {
        return switch (self) {
            .insert, .command => true,
            .normal, .select => false,
        };
    }

    /// Check if mode shows selections
    pub fn showsSelections(self: Mode) bool {
        return switch (self) {
            .select => true,
            .normal, .insert, .command => false,
        };
    }
};

/// Mode transition event
pub const Transition = struct {
    from: Mode,
    to: Mode,
    timestamp: i64,

    pub fn init(from: Mode, to: Mode) Transition {
        return .{
            .from = from,
            .to = to,
            .timestamp = std.time.milliTimestamp(),
        };
    }
};

/// Mode manager - handles mode state and transitions
pub const ModeManager = struct {
    current: Mode,
    previous: Mode,
    history: std.BoundedArray(Transition, 100),

    /// Initialize in normal mode
    pub fn init() ModeManager {
        return .{
            .current = .normal,
            .previous = .normal,
            .history = .{},
        };
    }

    /// Get current mode
    pub fn getMode(self: *const ModeManager) Mode {
        return self.current;
    }

    /// Get previous mode
    pub fn getPreviousMode(self: *const ModeManager) Mode {
        return self.previous;
    }

    /// Attempt to transition to a new mode
    pub fn transitionTo(self: *ModeManager, new_mode: Mode) !void {
        if (self.current == new_mode) return;

        // Validate transition
        if (!self.isValidTransition(self.current, new_mode)) {
            return error.InvalidModeTransition;
        }

        // Record transition
        const transition = Transition.init(self.current, new_mode);
        self.history.append(transition) catch {}; // Ignore if history is full

        // Update state
        self.previous = self.current;
        self.current = new_mode;
    }

    /// Enter normal mode
    pub fn enterNormal(self: *ModeManager) !void {
        try self.transitionTo(.normal);
    }

    /// Enter insert mode
    pub fn enterInsert(self: *ModeManager) !void {
        try self.transitionTo(.insert);
    }

    /// Enter select mode
    pub fn enterSelect(self: *ModeManager) !void {
        try self.transitionTo(.select);
    }

    /// Enter command mode
    pub fn enterCommand(self: *ModeManager) !void {
        try self.transitionTo(.command);
    }

    /// Return to previous mode
    pub fn returnToPrevious(self: *ModeManager) !void {
        try self.transitionTo(self.previous);
    }

    /// Check if transition is valid
    fn isValidTransition(self: *const ModeManager, from: Mode, to: Mode) bool {
        _ = self;

        // All transitions are valid for now
        // In the future, we might restrict certain transitions
        // For example: select -> insert might be disallowed

        // Common patterns:
        // - Escape from any mode -> normal
        // - Normal -> insert (i, a, o, etc.)
        // - Normal -> select (v, V)
        // - Normal -> command (:)
        // - Insert -> normal (Escape)
        // - Select -> normal (Escape)
        // - Command -> normal (Escape, Enter)

        _ = from;
        _ = to;
        return true;
    }

    /// Get transition history
    pub fn getHistory(self: *const ModeManager) []const Transition {
        return self.history.constSlice();
    }

    /// Clear transition history
    pub fn clearHistory(self: *ModeManager) void {
        self.history.len = 0;
    }
};

test "mode: init" {
    var manager = ModeManager.init();
    try std.testing.expectEqual(Mode.normal, manager.getMode());
}

test "mode: transitions" {
    var manager = ModeManager.init();

    try manager.enterInsert();
    try std.testing.expectEqual(Mode.insert, manager.getMode());
    try std.testing.expectEqual(Mode.normal, manager.getPreviousMode());

    try manager.enterNormal();
    try std.testing.expectEqual(Mode.normal, manager.getMode());
    try std.testing.expectEqual(Mode.insert, manager.getPreviousMode());

    try manager.enterSelect();
    try std.testing.expectEqual(Mode.select, manager.getMode());

    try manager.enterCommand();
    try std.testing.expectEqual(Mode.command, manager.getMode());
}

test "mode: return to previous" {
    var manager = ModeManager.init();

    try manager.enterInsert();
    try manager.enterNormal();
    try manager.returnToPrevious();

    try std.testing.expectEqual(Mode.insert, manager.getMode());
}

test "mode: history tracking" {
    var manager = ModeManager.init();

    try manager.enterInsert();
    try manager.enterNormal();
    try manager.enterSelect();

    const history = manager.getHistory();
    try std.testing.expectEqual(@as(usize, 3), history.len);
    try std.testing.expectEqual(Mode.normal, history[0].from);
    try std.testing.expectEqual(Mode.insert, history[0].to);
}

test "mode: names" {
    try std.testing.expectEqualStrings("NORMAL", Mode.normal.name());
    try std.testing.expectEqualStrings("INSERT", Mode.insert.name());
    try std.testing.expectEqualStrings("N", Mode.normal.shortName());
    try std.testing.expectEqualStrings("I", Mode.insert.shortName());
}

test "mode: capabilities" {
    try std.testing.expect(Mode.insert.acceptsTextInput());
    try std.testing.expect(!Mode.normal.acceptsTextInput());
    try std.testing.expect(Mode.select.showsSelections());
    try std.testing.expect(!Mode.normal.showsSelections());
}
