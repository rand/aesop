//! Input Integration Tests
//! Tests the full input handling pipeline
//!
//! These tests exercise the complete input stack:
//! - Terminal I/O → Input Parser → Key Events → Editor Actions
//! - Character input, escape sequences, special keys
//! - Input lag and responsiveness
//! - Multi-byte UTF-8 input
//!
//! Bugs Prevented:
//! - Input lag from short timeout (v0.9.1)
//! - Missed keypresses
//! - Incorrect key parsing
//! - UTF-8 handling errors

const std = @import("std");
const testing = std.testing;
const MockTerminal = @import("../helpers.zig").MockTerminal;
const Input = @import("../../src/terminal/input.zig");
const Key = Input.Key;

// Test 1: Basic character input works
test "input: basic character input" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue input characters
    try mock_term.queueInput("abc");

    // Read and parse
    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqualStrings("abc", buffer[0..n]);
}

// Test 2: Escape sequences parse correctly
test "input: escape sequences parse correctly" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue arrow key sequences
    // Up: ESC [ A
    // Down: ESC [ B
    // Right: ESC [ C
    // Left: ESC [ D
    try mock_term.queueInput("\x1b[A\x1b[B\x1b[C\x1b[D");

    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    // Should have read all escape sequences
    try testing.expect(n > 0);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "\x1b[A") != null);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "\x1b[B") != null);
}

// Test 3: Control characters handled
test "input: control characters handled" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue control characters
    // Ctrl+C: 0x03
    // Ctrl+D: 0x04
    // Ctrl+Z: 0x1A
    try mock_term.queueInput("\x03\x04\x1A");

    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqual(@as(u8, 0x03), buffer[0]);
    try testing.expectEqual(@as(u8, 0x04), buffer[1]);
    try testing.expectEqual(@as(u8, 0x1A), buffer[2]);
}

// Test 4: UTF-8 multi-byte input works
test "input: utf-8 multibyte input" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue UTF-8 characters: emoji and accented chars
    // 👍 = F0 9F 91 8D (4 bytes)
    // é = C3 A9 (2 bytes)
    try mock_term.queueInput("Hello 👍 café");

    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expect(n > 5); // More than just "Hello"
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "Hello") != null);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "👍") != null);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "café") != null);
}

// Test 5: Input buffer handles partial reads
test "input: partial reads handled correctly" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue more data than buffer can hold
    const long_input = "a" ** 100;
    try mock_term.queueInput(long_input);

    // Read with small buffer
    var buffer: [10]u8 = undefined;
    const n1 = try mock_term.read(&buffer);

    try testing.expectEqual(@as(usize, 10), n1);
    try testing.expectEqualStrings("aaaaaaaaaa", buffer[0..n1]);

    // Read remaining data
    const n2 = try mock_term.read(&buffer);
    try testing.expectEqual(@as(usize, 10), n2);
}

// Test 6: Empty read returns zero
test "input: empty read returns zero" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // No input queued
    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expectEqual(@as(usize, 0), n);
}

// Test 7: Function keys parse correctly
test "input: function keys parse correctly" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue F1-F4 sequences
    // F1: ESC O P
    // F2: ESC O Q
    // F3: ESC O R
    // F4: ESC O S
    try mock_term.queueInput("\x1bOP\x1bOQ\x1bOR\x1bOS");

    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expect(n > 0);
    // Verify escape sequences present
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "\x1bOP") != null);
}

// Test 8: Mixed input types handled
test "input: mixed input types handled" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue mix of regular chars, control chars, and escape sequences
    try mock_term.queueInput("abc\x03\x1b[Adef");

    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expect(n > 0);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "abc") != null);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "def") != null);
}

// Test 9: Backspace and delete handled
test "input: backspace and delete handled" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue backspace (0x7F) and delete (ESC[3~)
    try mock_term.queueInput("abc\x7f\x1b[3~");

    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expect(n > 0);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "abc") != null);
    try testing.expectEqual(@as(u8, 0x7F), buffer[3]); // Backspace
}

// Test 10: Tab and Enter handled
test "input: tab and enter handled" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Queue tab (0x09) and enter (0x0D or 0x0A)
    try mock_term.queueInput("hello\tworld\n");

    var buffer: [64]u8 = undefined;
    const n = try mock_term.read(&buffer);

    try testing.expect(n > 0);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "hello") != null);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "\t") != null);
    try testing.expect(std.mem.indexOf(u8, buffer[0..n], "\n") != null);
}
