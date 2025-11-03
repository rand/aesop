//! Unit tests for Markdown to plain text conversion

const std = @import("std");
const testing = std.testing;
const Markdown = @import("../../src/render/markdown.zig");

test "markdown: plain text unchanged" {
    const allocator = testing.allocator;
    const input = "This is plain text.";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expectEqualStrings(input, output);
}

test "markdown: header conversion" {
    const allocator = testing.allocator;
    const input = "# Header 1\n## Header 2\n### Header 3";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "== Header 1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "== Header 2") != null);
    try testing.expect(std.mem.indexOf(u8, output, "== Header 3") != null);
}

test "markdown: bold removal" {
    const allocator = testing.allocator;
    const input = "This is **bold** text.";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expectEqualStrings("This is bold text.", output);
}

test "markdown: italic removal" {
    const allocator = testing.allocator;
    const input = "This is *italic* text.";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expectEqualStrings("This is italic text.", output);
}

test "markdown: inline code preservation" {
    const allocator = testing.allocator;
    const input = "Use `code` here.";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expectEqualStrings("Use code here.", output);
}

test "markdown: code block preservation" {
    const allocator = testing.allocator;
    const input =
        \\```zig
        \\const x = 42;
        \\```
    ;

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "const x = 42;") != null);
}

test "markdown: link text extraction" {
    const allocator = testing.allocator;
    const input = "Visit [Google](https://google.com) now.";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expectEqualStrings("Visit Google now.", output);
}

test "markdown: unordered list" {
    const allocator = testing.allocator;
    const input = "- Item 1\n- Item 2\n- Item 3";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "• Item 1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "• Item 2") != null);
}

test "markdown: ordered list" {
    const allocator = testing.allocator;
    const input = "1. First\n2. Second\n3. Third";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "First") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Second") != null);
}

test "markdown: multiple formatting" {
    const allocator = testing.allocator;
    const input = "# Title\nThis is **bold** and *italic* with `code`.";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "== Title") != null);
    try testing.expect(std.mem.indexOf(u8, output, "bold") != null);
    try testing.expect(std.mem.indexOf(u8, output, "italic") != null);
    try testing.expect(std.mem.indexOf(u8, output, "code") != null);
}

test "markdown: empty input" {
    const allocator = testing.allocator;
    const input = "";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expectEqualStrings("", output);
}

test "markdown: nested formatting" {
    const allocator = testing.allocator;
    const input = "**Bold with *italic* inside**";

    const output = try Markdown.toPlainText(allocator, input);
    defer allocator.free(output);

    try testing.expectEqualStrings("Bold with italic inside", output);
}
