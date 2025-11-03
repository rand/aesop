//! Unit tests for Rope data structure

const std = @import("std");
const testing = std.testing;
const Rope = @import("../../src/buffer/rope.zig").Rope;

test "rope: create empty" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try testing.expectEqual(@as(usize, 0), rope.len());
}

test "rope: insert text" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");
    try testing.expectEqual(@as(usize, 5), rope.len());

    const content = try rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("hello", content);
}

test "rope: insert at middle" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");
    try rope.insert(2, "XYZ");

    const content = try rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("heXYZllo", content);
}

test "rope: delete range" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello world");
    try rope.delete(5, 11); // Delete " world"

    const content = try rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("hello", content);
}

test "rope: multiple operations" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello");
    try rope.insert(5, " ");
    try rope.insert(6, "world");

    const content = try rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("hello world", content);
}

test "rope: line count" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "line1\nline2\nline3");

    const lines = rope.lineCount();
    try testing.expectEqual(@as(usize, 3), lines);
}

test "rope: get line" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "first\nsecond\nthird");

    const line = try rope.getLine(allocator, 1);
    defer allocator.free(line);
    try testing.expectEqualStrings("second", line);
}

test "rope: large text" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    // Insert 10KB of text
    var large_text = try allocator.alloc(u8, 10240);
    defer allocator.free(large_text);
    @memset(large_text, 'A');

    try rope.insert(0, large_text);
    try testing.expectEqual(@as(usize, 10240), rope.len());
}

test "rope: UTF-8 support" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "Hello, 世界!");

    const content = try rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("Hello, 世界!", content);
}

test "rope: slice extraction" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "hello world");

    const slice = try rope.slice(allocator, 0, 5);
    defer allocator.free(slice);
    try testing.expectEqualStrings("hello", slice);
}

test "rope: boundary conditions" {
    const allocator = testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    // Insert at end
    try rope.insert(0, "hello");
    try rope.insert(5, " world");

    // Delete at boundaries
    try rope.delete(5, 6); // Delete single space

    const content = try rope.toString(allocator);
    defer allocator.free(content);
    try testing.expectEqualStrings("helloworld", content);
}
