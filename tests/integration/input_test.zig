//! Input Integration Tests
//! Tests the full input handling pipeline

const std = @import("std");
const testing = std.testing;
const aesop = @import("aesop");
const MockTerminal = aesop.test_helpers.MockTerminal;

test "input: queue and read basic input" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    try mock_term.queueInput("hello");

    var buffer: [10]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expectEqual(@as(usize, 5), n);
    try testing.expectEqualStrings("hello", buffer[0..n]);
}

test "input: empty read returns zero" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var buffer: [10]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expectEqual(@as(usize, 0), n);
}

test "input: partial reads work correctly" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    try mock_term.queueInput("hello world");

    // Read only 5 bytes
    var buffer: [5]u8 = undefined;
    const n1 = try mock_term.read(&buffer);
    try testing.expectEqual(@as(usize, 5), n1);
    try testing.expectEqualStrings("hello", buffer[0..n1]);

    // Read remaining 6 bytes
    const n2 = try mock_term.read(&buffer);
    try testing.expectEqual(@as(usize, 5), n2);
    try testing.expectEqualStrings(" worl", buffer[0..n2]);
}

test "input: utf-8 multibyte characters" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    try mock_term.queueInput("café");

    var buffer: [10]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expect(n > 4); // "café" is 5 bytes (é is 2 bytes)
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "café") != null);
}

test "input: control characters handled" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue Ctrl+C (0x03)
    try mock_term.queueInput("\x03");

    var buffer: [10]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expectEqual(@as(usize, 1), n);
    try testing.expectEqual(@as(u8, 0x03), buffer[0]);
}
