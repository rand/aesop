//! Undo/redo system with branch support
//! Tracks text operations with cursor positions

const std = @import("std");
const Cursor = @import("cursor.zig");
const Rope = @import("../buffer/rope.zig").Rope;

/// Type of operation for undo/redo
pub const OperationType = enum {
    insert,
    delete,
    replace,
};

/// A single undoable operation
pub const Operation = struct {
    op_type: OperationType,
    position: Cursor.Position, // Where the operation occurred
    text: []const u8, // Text inserted/deleted/replaced
    old_text: ?[]const u8, // For replace operations
    timestamp: i64,

    pub fn init(
        allocator: std.mem.Allocator,
        op_type: OperationType,
        position: Cursor.Position,
        text: []const u8,
        old_text: ?[]const u8,
    ) !Operation {
        const owned_text = try allocator.dupe(u8, text);
        const owned_old_text = if (old_text) |old| try allocator.dupe(u8, old) else null;

        return .{
            .op_type = op_type,
            .position = position,
            .text = owned_text,
            .old_text = owned_old_text,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *Operation, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.old_text) |old| {
            allocator.free(old);
        }
    }
};

/// Group of operations that should be undone/redone together
pub const OperationGroup = struct {
    operations: std.ArrayList(Operation),
    cursor_before: Cursor.Position,
    cursor_after: Cursor.Position,
    timestamp: i64,

    pub fn init(allocator: std.mem.Allocator, cursor: Cursor.Position) OperationGroup {
        return .{
            .operations = std.ArrayList(Operation).init(allocator),
            .cursor_before = cursor,
            .cursor_after = cursor,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *OperationGroup, allocator: std.mem.Allocator) void {
        for (self.operations.items) |*op| {
            op.deinit(allocator);
        }
        self.operations.deinit(allocator);
    }

    pub fn addOperation(self: *OperationGroup, op: Operation) !void {
        try self.operations.append(op);
        self.cursor_after = op.position;
    }

    /// Check if this group can be merged with another (for rapid typing)
    pub fn canMerge(self: *const OperationGroup, other: *const OperationGroup) bool {
        // Merge if within 1 second and both are inserts
        const time_diff = @abs(other.timestamp - self.timestamp);
        if (time_diff > 1000) return false;

        // Only merge insert operations
        for (self.operations.items) |op| {
            if (op.op_type != .insert) return false;
        }
        for (other.operations.items) |op| {
            if (op.op_type != .insert) return false;
        }

        return true;
    }
};

/// Undo history with branch support (vim-style undo tree)
pub const UndoHistory = struct {
    groups: std.ArrayList(OperationGroup),
    current_index: usize, // Points to the operation we'd undo next
    allocator: std.mem.Allocator,

    /// Max groups to keep (to prevent unbounded memory growth)
    const MAX_GROUPS = 1000;

    pub fn init(allocator: std.mem.Allocator) UndoHistory {
        return .{
            .groups = std.ArrayList(OperationGroup).empty,
            .current_index = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UndoHistory) void {
        for (self.groups.items) |*group| {
            group.deinit(self.allocator);
        }
        self.groups.deinit(self.allocator);
    }

    /// Add an operation group to history
    pub fn push(self: *UndoHistory, group: OperationGroup) !void {
        // If we're not at the end, we're creating a new branch
        // For simplicity, we'll discard the future for now (TODO: proper branching)
        if (self.current_index < self.groups.items.len) {
            // Free discarded groups
            while (self.current_index < self.groups.items.len) {
                var discarded = self.groups.pop();
                discarded.deinit(self.allocator);
            }
        }

        // Check if we can merge with previous group
        if (self.groups.items.len > 0) {
            const last = &self.groups.items[self.groups.items.len - 1];
            if (last.canMerge(&group)) {
                // Merge operations into last group
                for (group.operations.items) |op| {
                    try last.operations.append(op);
                }
                last.cursor_after = group.cursor_after;
                last.timestamp = group.timestamp;
                // Don't deinit group since we transferred ownership of operations
                return;
            }
        }

        // Add new group
        try self.groups.append(group);
        self.current_index = self.groups.items.len;

        // Enforce max size
        if (self.groups.items.len > MAX_GROUPS) {
            var oldest = self.groups.orderedRemove(0);
            oldest.deinit(self.allocator);
            self.current_index -= 1;
        }
    }

    /// Get the next group to undo (returns null if at beginning)
    pub fn getUndo(self: *UndoHistory) ?*OperationGroup {
        if (self.current_index == 0) return null;
        self.current_index -= 1;
        return &self.groups.items[self.current_index];
    }

    /// Get the next group to redo (returns null if at end)
    pub fn getRedo(self: *UndoHistory) ?*OperationGroup {
        if (self.current_index >= self.groups.items.len) return null;
        const group = &self.groups.items[self.current_index];
        self.current_index += 1;
        return group;
    }

    /// Check if undo is available
    pub fn canUndo(self: *const UndoHistory) bool {
        return self.current_index > 0;
    }

    /// Check if redo is available
    pub fn canRedo(self: *const UndoHistory) bool {
        return self.current_index < self.groups.items.len;
    }

    /// Apply an operation group to a rope (for undo - reverse operations)
    pub fn applyUndo(group: *const OperationGroup, rope: *Rope, allocator: std.mem.Allocator) !void {
        // Apply operations in reverse order
        var i = group.operations.items.len;
        while (i > 0) {
            i -= 1;
            const op = group.operations.items[i];

            // Convert position to byte offset
            const offset = try positionToOffset(rope, op.position, allocator);

            switch (op.op_type) {
                .insert => {
                    // Undo insert: delete the inserted text
                    try rope.delete(offset, offset + op.text.len);
                },
                .delete => {
                    // Undo delete: re-insert the deleted text
                    try rope.insert(offset, op.text);
                },
                .replace => {
                    // Undo replace: restore old text
                    if (op.old_text) |old| {
                        try rope.delete(offset, offset + op.text.len);
                        try rope.insert(offset, old);
                    }
                },
            }
        }
    }

    /// Apply an operation group to a rope (for redo - forward operations)
    pub fn applyRedo(group: *const OperationGroup, rope: *Rope, allocator: std.mem.Allocator) !void {
        // Apply operations in forward order
        for (group.operations.items) |op| {
            // Convert position to byte offset
            const offset = try positionToOffset(rope, op.position, allocator);

            switch (op.op_type) {
                .insert => {
                    // Redo insert: insert the text
                    try rope.insert(offset, op.text);
                },
                .delete => {
                    // Redo delete: delete the text
                    try rope.delete(offset, offset + op.text.len);
                },
                .replace => {
                    // Redo replace: apply new text
                    if (op.old_text) |old| {
                        try rope.delete(offset, offset + old.len);
                        try rope.insert(offset, op.text);
                    }
                },
            }
        }
    }
};

/// Convert Position (line, col) to byte offset in rope
fn positionToOffset(rope: *const Rope, pos: Cursor.Position, allocator: std.mem.Allocator) !usize {
    const text = try rope.toString(allocator);
    defer allocator.free(text);

    var offset: usize = 0;
    var line: usize = 0;
    var col: usize = 0;

    while (offset < text.len) {
        if (line == pos.line and col == pos.col) {
            return offset;
        }

        if (text[offset] == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
        offset += 1;
    }

    // If we reach here, position is at or beyond end of file
    return offset;
}

// === Tests ===

test "operation: init and deinit" {
    const allocator = std.testing.allocator;

    var op = try Operation.init(
        allocator,
        .insert,
        .{ .line = 0, .col = 0 },
        "test",
        null,
    );
    defer op.deinit(allocator);

    try std.testing.expectEqualStrings("test", op.text);
}

test "operation group: merge" {
    const allocator = std.testing.allocator;

    var g1 = OperationGroup.init(allocator, .{ .line = 0, .col = 0 });
    defer g1.deinit(allocator);

    var g2 = OperationGroup.init(allocator, .{ .line = 0, .col = 1 });
    defer g2.deinit(allocator);

    const op1 = try Operation.init(allocator, .insert, .{ .line = 0, .col = 0 }, "a", null);
    try g1.addOperation(op1);

    const op2 = try Operation.init(allocator, .insert, .{ .line = 0, .col = 1 }, "b", null);
    try g2.addOperation(op2);

    try std.testing.expect(g1.canMerge(&g2));
}

test "undo history: push and undo" {
    const allocator = std.testing.allocator;
    var history = UndoHistory.init(allocator);
    defer history.deinit();

    var group = OperationGroup.init(allocator, .{ .line = 0, .col = 0 });
    const op = try Operation.init(allocator, .insert, .{ .line = 0, .col = 0 }, "test", null);
    try group.addOperation(op);

    try history.push(group);

    try std.testing.expect(history.canUndo());
    try std.testing.expect(!history.canRedo());

    const undo_group = history.getUndo();
    try std.testing.expect(undo_group != null);
    try std.testing.expect(!history.canUndo());
    try std.testing.expect(history.canRedo());
}

test "undo history: redo" {
    const allocator = std.testing.allocator;
    var history = UndoHistory.init(allocator);
    defer history.deinit();

    var group = OperationGroup.init(allocator, .{ .line = 0, .col = 0 });
    const op = try Operation.init(allocator, .insert, .{ .line = 0, .col = 0 }, "test", null);
    try group.addOperation(op);

    try history.push(group);

    _ = history.getUndo();
    try std.testing.expect(history.canRedo());

    const redo_group = history.getRedo();
    try std.testing.expect(redo_group != null);
    try std.testing.expect(!history.canRedo());
}
