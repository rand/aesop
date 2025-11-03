//! E2E tests for writer persona workflow
//! Simulates a writer editing prose documents

const std = @import("std");
const testing = std.testing;
const Helpers = @import("../helpers.zig");
const Buffer = @import("../../src/buffer/manager.zig").Buffer;
const Actions = @import("../../src/editor/actions.zig");
const Cursor = @import("../../src/editor/cursor.zig");

test "writer persona: compose paragraph" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, "essay.md");
    defer buffer.deinit();

    // Writer composes a paragraph
    const para1 = "The quick brown fox jumps over the lazy dog. ";
    const para2 = "This sentence contains every letter of the alphabet. ";
    const para3 = "Writers often use this phrase to test fonts and layouts.\n\n";

    try buffer.rope.insert(0, para1);
    try buffer.rope.insert(para1.len, para2);
    try buffer.rope.insert(para1.len + para2.len, para3);

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "quick brown fox") != null);
    try testing.expect(std.mem.indexOf(u8, content, "alphabet") != null);
}

test "writer persona: edit and revise sentence" {
    const allocator = testing.allocator;

    const draft = "The cat sat on the mat.\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(draft);
    defer buffer.deinit();

    // Revise: change "cat" to "dog"
    const cat_pos = std.mem.indexOf(u8, draft, "cat").?;
    try buffer.rope.delete(cat_pos, 3); // Delete "cat"
    try buffer.rope.insert(cat_pos, "dog");

    const revised = try buffer.rope.toString(allocator);
    defer allocator.free(revised);

    try testing.expectEqualStrings("The dog sat on the mat.\n", revised);
}

test "writer persona: search and replace" {
    const allocator = testing.allocator;

    const text =
        \\Alice walked to the store.
        \\Alice bought some milk.
        \\Alice returned home.
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(text);
    defer buffer.deinit();

    // Find all occurrences of "Alice" (would use search in real workflow)
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, content, pos, "Alice")) |found| {
        count += 1;
        pos = found + 5; // Length of "Alice"
    }

    try testing.expectEqual(@as(usize, 3), count);
}

test "writer persona: markdown formatting" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, "notes.md");
    defer buffer.deinit();

    // Add markdown elements
    const title = "# My Notes\n\n";
    const heading = "## Important Ideas\n\n";
    const list = "- First idea\n- Second idea\n- Third idea\n\n";
    const bold = "This is **bold** text.\n";

    try buffer.rope.insert(0, title);
    try buffer.rope.insert(title.len, heading);
    try buffer.rope.insert(title.len + heading.len, list);
    try buffer.rope.insert(title.len + heading.len + list.len, bold);

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "# My Notes") != null);
    try testing.expect(std.mem.indexOf(u8, content, "## Important Ideas") != null);
    try testing.expect(std.mem.indexOf(u8, content, "**bold**") != null);
}

test "writer persona: long document navigation" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, "novel.txt");
    defer buffer.deinit();

    // Create a long document
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var line_buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "Chapter {d}: Lorem ipsum dolor sit amet.\n", .{i + 1});
        try buffer.rope.insert(buffer.rope.len(), line);
    }

    try testing.expect(buffer.lineCount() >= 100);

    // Navigate to specific line (line 50)
    const line50 = try buffer.rope.getLine(allocator, 50);
    defer allocator.free(line50);

    try testing.expect(std.mem.indexOf(u8, line50, "Chapter 51") != null);
}

test "writer persona: copy and paste paragraphs" {
    const allocator = testing.allocator;

    const doc =
        \\Paragraph one is here.
        \\
        \\Paragraph two follows.
        \\
        \\Paragraph three concludes.
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(doc);
    defer buffer.deinit();

    var clipboard = Actions.Clipboard.init(allocator);
    defer clipboard.deinit();

    // Select and copy "Paragraph two follows."
    const para2_start = std.mem.indexOf(u8, doc, "Paragraph two").?;
    const para2_end = para2_start + "Paragraph two follows.".len;

    const selection = Cursor.Selection.init(
        Cursor.Position{ .line = 2, .col = 0 },
        Cursor.Position{ .line = 2, .col = 22 },
    );

    try Actions.yankSelection(&buffer, selection, &clipboard);

    const yanked = clipboard.getContent();
    try testing.expect(yanked != null);
    try testing.expect(std.mem.indexOf(u8, yanked.?, "Paragraph two") != null);
}

test "writer persona: undo editing mistakes" {
    const allocator = testing.allocator;

    const original = "This is the correct text.\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(original);
    defer buffer.deinit();

    // Make a mistake: delete important word
    const mistake_pos = std.mem.indexOf(u8, original, "correct").?;
    try buffer.rope.delete(mistake_pos, 7); // Delete "correct"

    const mistake = try buffer.rope.toString(allocator);
    defer allocator.free(mistake);

    try testing.expect(std.mem.indexOf(u8, mistake, "correct") == null);

    // In real workflow, undo would restore original
    // For now, just verify buffer state changed
    try testing.expect(mistake.len < original.len);
}

test "writer persona: spell check workflow" {
    const allocator = testing.allocator;

    const text = "The qwick brown fox jumps ovr the lazy dog.\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(text);
    defer buffer.deinit();

    // Simulate spell checker finding "qwick" and "ovr"
    // In real workflow, diagnostics would highlight these
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "qwick") != null);
    try testing.expect(std.mem.indexOf(u8, content, "ovr") != null);
}

test "writer persona: word count tracking" {
    const allocator = testing.allocator;

    const essay =
        \\The art of writing involves careful word choice.
        \\Each sentence should convey clear meaning.
        \\Writers craft their prose with intention.
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(essay);
    defer buffer.deinit();

    // Count words (simple whitespace split)
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    var word_count: usize = 0;
    var iter = std.mem.tokenizeAny(u8, content, " \n\t");
    while (iter.next()) |_| {
        word_count += 1;
    }

    try testing.expect(word_count > 15); // At least 15 words
}
