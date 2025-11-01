//! Selection-first cursor and selection system
//! Inspired by Kakoune/Helix - selections are primary, cursor is secondary

const std = @import("std");

/// Position in buffer (byte-based)
pub const Position = struct {
    line: usize,
    col: usize, // Column in characters (not bytes)

    pub fn eql(self: Position, other: Position) bool {
        return self.line == other.line and self.col == other.col;
    }

    pub fn lessThan(self: Position, other: Position) bool {
        if (self.line < other.line) return true;
        if (self.line > other.line) return false;
        return self.col < other.col;
    }

    pub fn greaterThan(self: Position, other: Position) bool {
        return other.lessThan(self);
    }
};

/// Selection direction
pub const Direction = enum {
    forward,  // anchor < head
    backward, // head < anchor

    pub fn reverse(self: Direction) Direction {
        return switch (self) {
            .forward => .backward,
            .backward => .forward,
        };
    }
};

/// A selection range with anchor and head
/// - anchor: The start point of the selection (fixed during extension)
/// - head: The moving end of the selection (cursor position)
/// - direction: Which way the selection extends
pub const Selection = struct {
    anchor: Position,
    head: Position,

    /// Create a collapsed selection (cursor) at position
    pub fn cursor(pos: Position) Selection {
        return .{
            .anchor = pos,
            .head = pos,
        };
    }

    /// Create a selection from anchor to head
    pub fn init(anchor: Position, head: Position) Selection {
        return .{
            .anchor = anchor,
            .head = head,
        };
    }

    /// Get the direction of this selection
    pub fn direction(self: Selection) Direction {
        if (self.head.lessThan(self.anchor)) {
            return .backward;
        }
        return .forward;
    }

    /// Check if selection is collapsed (cursor)
    pub fn isCollapsed(self: Selection) bool {
        return self.anchor.eql(self.head);
    }

    /// Get the start of the selection (min of anchor and head)
    pub fn start(self: Selection) Position {
        return if (self.anchor.lessThan(self.head)) self.anchor else self.head;
    }

    /// Get the end of the selection (max of anchor and head)
    pub fn end(self: Selection) Position {
        return if (self.anchor.greaterThan(self.head)) self.anchor else self.head;
    }

    /// Get the range as (start, end) tuple
    pub fn range(self: Selection) struct { start: Position, end: Position } {
        return .{ .start = self.start(), .end = self.end() };
    }

    /// Move the head to a new position (extend selection)
    pub fn moveTo(self: Selection, new_head: Position) Selection {
        return .{
            .anchor = self.anchor,
            .head = new_head,
        };
    }

    /// Move both anchor and head by delta (translate selection)
    pub fn translate(self: Selection, delta_line: isize, delta_col: isize) Selection {
        return .{
            .anchor = translatePos(self.anchor, delta_line, delta_col),
            .head = translatePos(self.head, delta_line, delta_col),
        };
    }

    /// Collapse selection to head position
    pub fn collapseToHead(self: Selection) Selection {
        return cursor(self.head);
    }

    /// Collapse selection to anchor position
    pub fn collapseToAnchor(self: Selection) Selection {
        return cursor(self.anchor);
    }

    /// Flip the selection (swap anchor and head)
    pub fn flip(self: Selection) Selection {
        return .{
            .anchor = self.head,
            .head = self.anchor,
        };
    }

    fn translatePos(pos: Position, delta_line: isize, delta_col: isize) Position {
        const new_line = if (delta_line < 0)
            pos.line -| @abs(delta_line)
        else
            pos.line + @abs(delta_line);

        const new_col = if (delta_col < 0)
            pos.col -| @abs(delta_col)
        else
            pos.col + @abs(delta_col);

        return .{ .line = new_line, .col = new_col };
    }
};

/// Multiple selections manager
pub const SelectionSet = struct {
    selections: std.ArrayList(Selection),
    primary_index: usize, // Index of the primary selection

    /// Initialize empty selection set
    pub fn init(allocator: std.mem.Allocator) SelectionSet {
        return .{
            .selections = std.ArrayList(Selection).empty,
            .primary_index = 0,
        };
    }

    /// Initialize with a single cursor at (0, 0)
    pub fn initWithCursor(allocator: std.mem.Allocator, pos: Position) !SelectionSet {
        var set = init(allocator);
        try set.selections.append(allocator, Selection.cursor(pos));
        return set;
    }

    /// Clean up
    pub fn deinit(self: *SelectionSet, allocator: std.mem.Allocator) void {
        self.selections.deinit(allocator);
    }

    /// Get the primary selection
    pub fn primary(self: *const SelectionSet, allocator: std.mem.Allocator) ?Selection {
        const items = self.selections.items(allocator);
        if (self.primary_index < items.len) {
            return items[self.primary_index];
        }
        return null;
    }

    /// Get all selections
    pub fn all(self: *const SelectionSet, allocator: std.mem.Allocator) []const Selection {
        return self.selections.items(allocator);
    }

    /// Set selections (replaces all)
    pub fn setSelections(self: *SelectionSet, allocator: std.mem.Allocator, new_selections: []const Selection) !void {
        self.selections.deinit(allocator);
        self.selections = .empty;

        for (new_selections) |sel| {
            try self.selections.append(allocator, sel);
        }

        self.primary_index = 0;
    }

    /// Add a selection
    pub fn add(self: *SelectionSet, allocator: std.mem.Allocator, selection: Selection) !void {
        try self.selections.append(allocator, selection);
    }

    /// Clear all selections
    pub fn clear(self: *SelectionSet, allocator: std.mem.Allocator) void {
        self.selections.deinit(allocator);
        self.selections = .empty;
        self.primary_index = 0;
    }

    /// Set single cursor (clears all other selections)
    pub fn setSingleCursor(self: *SelectionSet, allocator: std.mem.Allocator, pos: Position) !void {
        self.clear(allocator);
        try self.selections.append(allocator, Selection.cursor(pos));
        self.primary_index = 0;
    }

    /// Count selections
    pub fn count(self: *const SelectionSet, allocator: std.mem.Allocator) usize {
        return self.selections.len(allocator);
    }

    /// Check if there are multiple selections
    pub fn hasMultiple(self: *const SelectionSet, allocator: std.mem.Allocator) bool {
        return self.count(allocator) > 1;
    }
};

test "position: comparison" {
    const p1 = Position{ .line = 0, .col = 0 };
    const p2 = Position{ .line = 0, .col = 5 };
    const p3 = Position{ .line = 1, .col = 0 };

    try std.testing.expect(p1.lessThan(p2));
    try std.testing.expect(p1.lessThan(p3));
    try std.testing.expect(p2.lessThan(p3));
    try std.testing.expect(!p2.lessThan(p1));
}

test "selection: cursor" {
    const pos = Position{ .line = 5, .col = 10 };
    const sel = Selection.cursor(pos);

    try std.testing.expect(sel.isCollapsed());
    try std.testing.expect(sel.anchor.eql(pos));
    try std.testing.expect(sel.head.eql(pos));
}

test "selection: direction" {
    const p1 = Position{ .line = 0, .col = 0 };
    const p2 = Position{ .line = 0, .col = 5 };

    const forward_sel = Selection.init(p1, p2);
    try std.testing.expectEqual(Direction.forward, forward_sel.direction());

    const backward_sel = Selection.init(p2, p1);
    try std.testing.expectEqual(Direction.backward, backward_sel.direction());
}

test "selection: range" {
    const p1 = Position{ .line = 0, .col = 0 };
    const p2 = Position{ .line = 0, .col = 5 };

    const sel = Selection.init(p1, p2);
    const r = sel.range();

    try std.testing.expect(r.start.eql(p1));
    try std.testing.expect(r.end.eql(p2));
}

test "selection: flip" {
    const p1 = Position{ .line = 0, .col = 0 };
    const p2 = Position{ .line = 0, .col = 5 };

    const sel = Selection.init(p1, p2);
    const flipped = sel.flip();

    try std.testing.expect(flipped.anchor.eql(p2));
    try std.testing.expect(flipped.head.eql(p1));
}

test "selection: translate" {
    const pos = Position{ .line = 5, .col = 10 };
    const sel = Selection.cursor(pos);

    const translated = sel.translate(2, 3);
    try std.testing.expectEqual(@as(usize, 7), translated.head.line);
    try std.testing.expectEqual(@as(usize, 13), translated.head.col);
}

test "selection set: init with cursor" {
    const allocator = std.testing.allocator;
    const pos = Position{ .line = 0, .col = 0 };

    var set = try SelectionSet.initWithCursor(allocator, pos);
    defer set.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), set.count(allocator));

    const prim = set.primary(allocator).?;
    try std.testing.expect(prim.isCollapsed());
}
