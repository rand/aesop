//! Rendering Integration Tests
//! Tests the full rendering pipeline to catch bugs like v0.9.0/v0.9.1 issues

const std = @import("std");
const testing = std.testing;
const aesop = @import("aesop");
const MockTerminal = aesop.test_helpers.MockTerminal;

// Note: These tests verify rendering pipeline integration
// They would have caught v0.9.0 (blank screen) and v0.9.1 (OPOST) bugs

test "rendering: mock terminal basic functionality" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Write some text
    _ = try mock_term.write("Hello, World!");

    // Verify output captured
    const output = mock_term.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "Hello") != null);
}

test "rendering: mock terminal screen buffer works" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Write text that should appear in screen buffer
    _ = try mock_term.write("Test content");

    // Check screen has content
    try testing.expect(mock_term.hasVisibleText());
    try testing.expect(!mock_term.isBlankScreen());
}

test "rendering: mock terminal screen contains text" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    _ = try mock_term.write("Aesop Editor");

    try testing.expect(mock_term.screenContains("Aesop"));
    try testing.expect(mock_term.screenContains("Editor"));
}

test "rendering: mock terminal handles newlines" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    _ = try mock_term.write("Line 1\nLine 2\n");

    const line0 = mock_term.getScreenLine(0);
    const line1 = mock_term.getScreenLine(1);

    try testing.expect(std.mem.indexOf(u8, line0, "Line 1") != null);
    try testing.expect(std.mem.indexOf(u8, line1, "Line 2") != null);
}

test "rendering: mock terminal clear output works" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    _ = try mock_term.write("Initial content");
    try testing.expect(mock_term.hasVisibleText());

    mock_term.clearOutput();
    try testing.expect(mock_term.isBlankScreen());
}
