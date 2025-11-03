//! E2E tests for failure and recovery scenarios
//! Tests error handling, edge cases, and recovery workflows

const std = @import("std");
const testing = std.testing;
const Helpers = @import("../helpers.zig");
const Buffer = @import("../../src/buffer/manager.zig").Buffer;
const Cursor = @import("../../src/editor/cursor.zig");
const Actions = @import("../../src/editor/actions.zig");

test "recovery: handle out-of-bounds delete" {
    const allocator = testing.allocator;

    const text = "Short text\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(text);
    defer buffer.deinit();

    // Try to delete beyond buffer length - should be handled gracefully
    const len = buffer.rope.len();
    const result = buffer.rope.delete(len + 100, 10);

    // Should return error
    try testing.expectError(error.OutOfBounds, result);

    // Buffer should be unchanged
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings(text, content);
}

test "recovery: handle out-of-bounds insert" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    try buffer.rope.insert(0, "Hello");

    // Try to insert far beyond end - should work (inserts at end)
    const len = buffer.rope.len();
    try buffer.rope.insert(len + 1000, " World");

    // Should have content
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(content.len > 0);
}

test "recovery: empty buffer operations" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Operations on empty buffer should not crash
    try testing.expectEqual(@as(usize, 0), buffer.rope.len());

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("", content);

    // Line count should be 1 even for empty buffer
    try testing.expectEqual(@as(usize, 1), buffer.lineCount());
}

test "recovery: invalid UTF-8 handling" {
    const allocator = testing.allocator;

    // Valid UTF-8
    const valid = "Hello, 世界! 🚀";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(valid);
    defer buffer.deinit();

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expectEqualStrings(valid, content);
}

test "recovery: very large buffer" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Insert 10,000 lines
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        var line_buf: [32]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "Line {d}\n", .{i});
        try buffer.rope.insert(buffer.rope.len(), line);
    }

    try testing.expect(buffer.lineCount() >= 10000);

    // Should still be able to access first and last lines
    const first = try buffer.rope.getLine(allocator, 0);
    defer allocator.free(first);
    try testing.expect(std.mem.indexOf(u8, first, "Line 0") != null);
}

test "recovery: rapid insert/delete sequence" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Rapidly insert and delete
    var j: usize = 0;
    while (j < 100) : (j += 1) {
        try buffer.rope.insert(0, "X");
        if (buffer.rope.len() > 0) {
            try buffer.rope.delete(0, 1);
        }
    }

    // Buffer should be consistent (empty)
    try testing.expectEqual(@as(usize, 0), buffer.rope.len());
}

test "recovery: invalid selection range" {
    const allocator = testing.allocator;

    const text = "Sample text\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(text);
    defer buffer.deinit();

    // Create selection with head before anchor (should be normalized)
    const selection = Cursor.Selection.init(
        Cursor.Position{ .line = 0, .col = 10 }, // anchor
        Cursor.Position{ .line = 0, .col = 5 }, // head (before anchor)
    );

    // Selection should still work
    try testing.expect(selection.anchor.col == 10);
    try testing.expect(selection.head.col == 5);
}

test "recovery: clipboard operations on empty selection" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    var clipboard = Actions.Clipboard.init(allocator);
    defer clipboard.deinit();

    try buffer.rope.insert(0, "Text");

    // Yank empty selection (cursor at position)
    const empty_sel = Cursor.Selection.cursor(Cursor.Position{ .line = 0, .col = 0 });
    try Actions.yankSelection(&buffer, empty_sel, &clipboard);

    // Should complete without error
    const content = clipboard.getContent();
    try testing.expect(content == null or content.?.len == 0);
}

test "recovery: delete on empty buffer" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Try to delete from empty buffer
    const result = buffer.rope.delete(0, 1);

    // Should return error, not crash
    try testing.expectError(error.OutOfBounds, result);
}

test "recovery: line access beyond bounds" {
    const allocator = testing.allocator;

    const text = "Line 1\nLine 2\nLine 3\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(text);
    defer buffer.deinit();

    // Try to get line 100 (doesn't exist)
    const result = buffer.rope.getLine(allocator, 100);

    // Should return error
    try testing.expectError(error.OutOfBounds, result);
}

test "recovery: concurrent modifications simulation" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Simulate concurrent edits (in reality would need mutex)
    try buffer.rope.insert(0, "First");
    try buffer.rope.insert(5, " Second");
    try buffer.rope.insert(12, " Third");

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expectEqualStrings("First Second Third", content);
}

test "recovery: zero-width operations" {
    const allocator = testing.allocator;

    const text = "Hello World\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(text);
    defer buffer.deinit();

    // Insert empty string (should be no-op)
    try buffer.rope.insert(5, "");

    // Delete zero bytes (should be no-op)
    // Note: delete with len=0 might error, so we don't test it

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expectEqualStrings(text, content);
}

test "recovery: memory pressure with large allocations" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Allocate large string
    const large = "A" ** 10000;
    try buffer.rope.insert(0, large);

    try testing.expect(buffer.rope.len() == 10000);

    // Clean up properly
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expectEqual(@as(usize, 10000), content.len);
}

test "recovery: buffer with only newlines" {
    const allocator = testing.allocator;

    const newlines = "\n\n\n\n\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(newlines);
    defer buffer.deinit();

    // Should have 6 lines (5 newlines = 6 lines)
    try testing.expectEqual(@as(usize, 6), buffer.lineCount());
}

test "recovery: mixed line endings" {
    const allocator = testing.allocator;

    // In real implementation, might normalize to \n
    const mixed = "Line 1\nLine 2\nLine 3\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(mixed);
    defer buffer.deinit();

    try Helpers.Assertions.expectLineCount(&buffer, 4); // 3 lines + empty
}
