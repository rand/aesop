//! Mark/bookmark system for quick navigation
//! Allows setting named marks at positions and jumping back to them

const std = @import("std");
const Cursor = @import("cursor.zig");

/// Named mark with position
pub const Mark = struct {
    name: u8, // Single character mark name (a-z, A-Z)
    position: Cursor.Position,
    buffer_id: usize, // Which buffer this mark belongs to
};

/// Mark registry
pub const MarkRegistry = struct {
    marks: std.AutoHashMap(u8, Mark),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MarkRegistry {
        return .{
            .marks = std.AutoHashMap(u8, Mark).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MarkRegistry) void {
        self.marks.deinit();
    }

    /// Set a mark at the given position
    pub fn setMark(
        self: *MarkRegistry,
        name: u8,
        position: Cursor.Position,
        buffer_id: usize,
    ) !void {
        // Validate mark name (a-z, A-Z)
        if (!isValidMarkName(name)) {
            return error.InvalidMarkName;
        }

        const mark = Mark{
            .name = name,
            .position = position,
            .buffer_id = buffer_id,
        };

        try self.marks.put(name, mark);
    }

    /// Get a mark by name
    pub fn getMark(self: *const MarkRegistry, name: u8) ?Mark {
        return self.marks.get(name);
    }

    /// Delete a mark
    pub fn deleteMark(self: *MarkRegistry, name: u8) void {
        _ = self.marks.remove(name);
    }

    /// Clear all marks
    pub fn clear(self: *MarkRegistry) void {
        self.marks.clearRetainingCapacity();
    }

    /// Get all marks (for listing)
    pub fn listMarks(self: *const MarkRegistry, allocator: std.mem.Allocator) ![]Mark {
        var list = std.ArrayList(Mark).init(allocator);
        errdefer list.deinit();

        var iter = self.marks.valueIterator();
        while (iter.next()) |mark| {
            try list.append(mark.*);
        }

        // Sort by name
        const marks = try list.toOwnedSlice();
        std.mem.sort(Mark, marks, {}, markLessThan);
        return marks;
    }

    fn markLessThan(_: void, a: Mark, b: Mark) bool {
        return a.name < b.name;
    }
};

/// Check if mark name is valid (a-z, A-Z)
fn isValidMarkName(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z');
}

// === Tests ===

test "marks: set and get" {
    const allocator = std.testing.allocator;
    var registry = MarkRegistry.init(allocator);
    defer registry.deinit();

    const pos = Cursor.Position{ .line = 10, .col = 5 };
    try registry.setMark('a', pos, 0);

    const mark = registry.getMark('a');
    try std.testing.expect(mark != null);
    try std.testing.expectEqual(@as(usize, 10), mark.?.position.line);
    try std.testing.expectEqual(@as(usize, 5), mark.?.position.col);
}

test "marks: invalid name" {
    const allocator = std.testing.allocator;
    var registry = MarkRegistry.init(allocator);
    defer registry.deinit();

    const pos = Cursor.Position{ .line = 0, .col = 0 };
    const result = registry.setMark('1', pos, 0);
    try std.testing.expectError(error.InvalidMarkName, result);
}

test "marks: list marks" {
    const allocator = std.testing.allocator;
    var registry = MarkRegistry.init(allocator);
    defer registry.deinit();

    try registry.setMark('a', .{ .line = 1, .col = 0 }, 0);
    try registry.setMark('b', .{ .line = 2, .col = 0 }, 0);
    try registry.setMark('z', .{ .line = 3, .col = 0 }, 0);

    const marks = try registry.listMarks(allocator);
    defer allocator.free(marks);

    try std.testing.expectEqual(@as(usize, 3), marks.len);
    try std.testing.expectEqual(@as(u8, 'a'), marks[0].name);
    try std.testing.expectEqual(@as(u8, 'b'), marks[1].name);
    try std.testing.expectEqual(@as(u8, 'z'), marks[2].name);
}
