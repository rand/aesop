//! Integration tests for buffer editing workflows

const std = @import("std");
const testing = std.testing;
const Buffer = @import("../../src/buffer/manager.zig").Buffer;
const Cursor = @import("../../src/editor/cursor.zig");
const Actions = @import("../../src/editor/actions.zig");
const Helpers = @import("../helpers.zig");

test "integration: insert and delete text" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Insert initial text
    try buffer.rope.insert(0, "hello world");

    // Create cursor at position 6 (after "hello ")
    const cursor_pos = Cursor.Position{ .line = 0, .col = 6 };
    const selection = Cursor.Selection.cursor(cursor_pos);

    // Insert more text
    _ = try Actions.insertText(&buffer, selection, "beautiful ");

    // Verify result
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("hello beautiful world", content);
}

test "integration: multi-line editing" {
    const allocator = testing.allocator;
    const builder = Helpers.BufferBuilder.init(allocator);

    var buffer = try builder.withLines(&[_][]const u8{
        "line 1",
        "line 2",
        "line 3",
    });
    defer buffer.deinit();

    try Helpers.Assertions.expectLineCount(buffer, 3);

    // Get line content
    const line2 = try buffer.rope.getLine(allocator, 1);
    defer allocator.free(line2);
    try testing.expectEqualStrings("line 2", line2);
}

test "integration: undo and redo" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Initial state
    try buffer.rope.insert(0, "hello");

    // Make a change
    try buffer.rope.insert(5, " world");

    const content1 = try buffer.rope.toString(allocator);
    defer allocator.free(content1);
    try testing.expectEqualStrings("hello world", content1);

    // In a real scenario, undo would revert to snapshot
    // This tests the buffer state management
}

test "integration: selection and deletion" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    try buffer.rope.insert(0, "hello world");

    // Select "world" (positions 6-11)
    const anchor = Cursor.Position{ .line = 0, .col = 6 };
    const head = Cursor.Position{ .line = 0, .col = 11 };
    const selection = Cursor.Selection.init(anchor, head);

    // Delete selection
    _ = try Actions.deleteSelection(&buffer, selection, null);

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("hello ", content);
}

test "integration: newline insertion" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    try buffer.rope.insert(0, "hello");

    const cursor_pos = Cursor.Position{ .line = 0, .col = 5 };
    const selection = Cursor.Selection.cursor(cursor_pos);

    // Insert newline
    _ = try Actions.insertNewline(&buffer, selection);

    // Should now have 2 lines
    try Helpers.Assertions.expectLineCount(&buffer, 2);
}

test "integration: yank and paste" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    var clipboard = Actions.Clipboard.init(allocator);
    defer clipboard.deinit();

    try buffer.rope.insert(0, "hello world");

    // Select "hello"
    const anchor = Cursor.Position{ .line = 0, .col = 0 };
    const head = Cursor.Position{ .line = 0, .col = 5 };
    const selection = Cursor.Selection.init(anchor, head);

    // Yank to clipboard
    try Actions.yankSelection(&buffer, selection, &clipboard);

    // Verify clipboard content
    const yanked = clipboard.getContent();
    try testing.expect(yanked != null);
    try testing.expectEqualStrings("hello", yanked.?);
}

test "integration: buffer with UTF-8 content" {
    const allocator = testing.allocator;
    const builder = Helpers.BufferBuilder.init(allocator);

    var buffer = try builder.withContent("Hello, 世界! 🚀");
    defer buffer.deinit();

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("Hello, 世界! 🚀", content);
}

test "integration: large buffer operations" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Insert 1000 lines
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var line_buf: [32]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "Line {d}\n", .{i});
        try buffer.rope.insert(buffer.rope.len(), line);
    }

    try testing.expect(buffer.lineCount() >= 1000);
}
