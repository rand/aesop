//! Unit tests for Cursor and Selection management

const std = @import("std");
const testing = std.testing;
const Cursor = @import("../../src/editor/cursor.zig");

test "cursor: position creation" {
    const pos = Cursor.Position{ .line = 5, .col = 10 };
    try testing.expectEqual(@as(usize, 5), pos.line);
    try testing.expectEqual(@as(usize, 10), pos.col);
}

test "cursor: selection init" {
    const anchor = Cursor.Position{ .line = 0, .col = 0 };
    const head = Cursor.Position{ .line = 0, .col = 5 };

    const sel = Cursor.Selection.init(anchor, head);
    try testing.expectEqual(@as(usize, 0), sel.anchor.line);
    try testing.expectEqual(@as(usize, 5), sel.head.col);
}

test "cursor: collapsed selection" {
    const pos = Cursor.Position{ .line = 2, .col = 3 };
    const sel = Cursor.Selection.cursor(pos);

    try testing.expect(sel.isCollapsed());
    try testing.expectEqual(pos.line, sel.anchor.line);
    try testing.expectEqual(pos.col, sel.head.col);
}

test "cursor: selection range" {
    const anchor = Cursor.Position{ .line = 1, .col = 5 };
    const head = Cursor.Position{ .line = 1, .col = 10 };
    const sel = Cursor.Selection.init(anchor, head);

    const range = sel.range();
    try testing.expectEqual(@as(usize, 1), range.start.line);
    try testing.expectEqual(@as(usize, 5), range.start.col);
    try testing.expectEqual(@as(usize, 1), range.end.line);
    try testing.expectEqual(@as(usize, 10), range.end.col);
}

test "cursor: selection set init" {
    const allocator = testing.allocator;
    var set = try Cursor.SelectionSet.single(allocator, Cursor.Position{ .line = 0, .col = 0 });
    defer set.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), set.selections.items.len);
}

test "cursor: add selection" {
    const allocator = testing.allocator;
    var set = try Cursor.SelectionSet.single(allocator, Cursor.Position{ .line = 0, .col = 0 });
    defer set.deinit(allocator);

    const sel2 = Cursor.Selection.cursor(Cursor.Position{ .line = 1, .col = 0 });
    try set.add(allocator, sel2);

    try testing.expectEqual(@as(usize, 2), set.selections.items.len);
}

test "cursor: get primary selection" {
    const allocator = testing.allocator;
    var set = try Cursor.SelectionSet.single(allocator, Cursor.Position{ .line = 5, .col = 10 });
    defer set.deinit(allocator);

    const primary = set.primary(allocator);
    try testing.expect(primary != null);
    try testing.expectEqual(@as(usize, 5), primary.?.head.line);
}

test "cursor: set selections" {
    const allocator = testing.allocator;
    var set = try Cursor.SelectionSet.single(allocator, Cursor.Position{ .line = 0, .col = 0 });
    defer set.deinit(allocator);

    const new_sels = [_]Cursor.Selection{
        Cursor.Selection.cursor(Cursor.Position{ .line = 1, .col = 0 }),
        Cursor.Selection.cursor(Cursor.Position{ .line = 2, .col = 0 }),
    };

    try set.setSelections(allocator, &new_sels);
    try testing.expectEqual(@as(usize, 2), set.selections.items.len);
}

test "cursor: move to position" {
    const sel = Cursor.Selection.cursor(Cursor.Position{ .line = 0, .col = 0 });
    const new_pos = Cursor.Position{ .line = 5, .col = 10 };

    const moved = sel.moveTo(new_pos);
    try testing.expectEqual(@as(usize, 5), moved.head.line);
    try testing.expectEqual(@as(usize, 10), moved.head.col);
}

test "cursor: extend selection" {
    const anchor = Cursor.Position{ .line = 0, .col = 0 };
    const sel = Cursor.Selection.cursor(anchor);

    const new_head = Cursor.Position{ .line = 0, .col = 10 };
    const extended = sel.extendTo(new_head);

    try testing.expect(!extended.isCollapsed());
    try testing.expectEqual(@as(usize, 0), extended.anchor.col);
    try testing.expectEqual(@as(usize, 10), extended.head.col);
}
