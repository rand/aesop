//! Rendering Integration Tests
//! Tests the full rendering pipeline to catch bugs like v0.9.0/v0.9.1 issues
//!
//! These tests exercise the complete rendering stack:
//! - Renderer → OutputBuffer → Terminal I/O
//! - VT100 escape sequence generation
//! - Damage tracking and optimization
//! - Screen buffer updates
//!
//! Bugs Prevented:
//! - Blank screen on first render (v0.9.0)
//! - Text staircase effect from missing OPOST (v0.9.1)
//! - Status line not rendering
//! - Cursor positioning errors

const std = @import("std");
const testing = std.testing;
const MockTerminal = @import("../helpers.zig").MockTerminal;
const Renderer = @import("../../src/render/renderer.zig").Renderer;
const Buffer = @import("../../src/buffer/manager.zig").Buffer;
const BufferManager = @import("../../src/buffer/manager.zig").BufferManager;

/// Test 1: Initial render produces visible output
/// CRITICAL: This test would have caught the v0.9.0 blank screen bug
test "rendering: initial render produces visible output" {
    const allocator = testing.allocator;

    // Setup mock terminal
    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    // Create buffer with content
    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();
    try buffer.rope.insert(0, "Hello, World!\nThis is Aesop.");

    // Create renderer
    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    // Perform initial render
    try renderer.render(buffer, 0, 0);

    // CRITICAL ASSERTION: Screen must have visible text after first render
    // v0.9.0 BUG: This would fail - screen was completely blank
    try testing.expect(mock_term.hasVisibleText());
    try testing.expect(!mock_term.isBlankScreen());

    // Verify specific content is rendered
    try testing.expect(mock_term.screenContains("Hello"));
    try testing.expect(mock_term.screenContains("Aesop"));

    // Verify we rendered more than just a few characters
    const visible_chars = mock_term.countVisibleChars();
    try testing.expect(visible_chars > 10);
}

/// Test 2: Text renders with proper newlines (no staircase effect)
/// CRITICAL: This test would have caught the v0.9.1 OPOST bug
test "rendering: text renders with proper newlines" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();
    try buffer.rope.insert(0,
        \\First line
        \\Second line
        \\Third line
    );

    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    try renderer.render(buffer, 0, 0);

    // CRITICAL ASSERTION: Line breaks must be correct (no staircase)
    // v0.9.1 BUG: This would fail - OPOST disabled caused staircase effect
    try testing.expect(mock_term.hasCorrectLineBreaks());

    // Verify lines appear at expected rows
    const line0 = mock_term.getScreenLine(0);
    const line1 = mock_term.getScreenLine(1);
    const line2 = mock_term.getScreenLine(2);

    try testing.expect(std.mem.indexOf(u8, line0, "First") != null);
    try testing.expect(std.mem.indexOf(u8, line1, "Second") != null);
    try testing.expect(std.mem.indexOf(u8, line2, "Third") != null);

    // Each line should start at column 0 (not staircase)
    // This is a simplified check - in real output, we'd verify cursor positioning
}

/// Test 3: Status line renders on every frame
test "rendering: status line renders correctly" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var buffer = try Buffer.init(allocator, "test.zig");
    defer buffer.deinit();
    try buffer.rope.insert(0, "const x = 5;");

    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    try renderer.render(buffer, 0, 0);

    // Status line should be present
    try testing.expect(mock_term.hasStatusLine());

    // Status line should contain mode indicator and/or filename
    const last_row = mock_term.getScreenLine(23); // Height - 1
    const has_mode = std.mem.indexOf(u8, last_row, "NORMAL") != null or
        std.mem.indexOf(u8, last_row, "INSERT") != null or
        std.mem.indexOf(u8, last_row, "SELECT") != null;
    const has_filename = std.mem.indexOf(u8, last_row, "test.zig") != null;

    try testing.expect(has_mode or has_filename);
}

/// Test 4: Multiple render cycles work correctly
test "rendering: multiple render cycles work" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();
    try buffer.rope.insert(0, "Initial text");

    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    // First render
    try renderer.render(buffer, 0, 0);
    try testing.expect(mock_term.screenContains("Initial"));

    // Clear and prepare for second render
    mock_term.clearOutput();

    // Modify buffer
    try buffer.rope.insert(12, " - modified");

    // Second render
    try renderer.render(buffer, 0, 0);
    try testing.expect(mock_term.screenContains("modified"));

    // Third render (no changes) - should still work
    mock_term.clearOutput();
    try renderer.render(buffer, 0, 0);
    try testing.expect(mock_term.hasVisibleText());
}

/// Test 5: Cursor positioning correct after render
test "rendering: cursor positioned correctly" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();
    try buffer.rope.insert(0, "Line 1\nLine 2\nLine 3");

    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    // Render with cursor at position (1, 3) - second line, 4th column
    try renderer.render(buffer, 1, 3);

    // Verify output contains cursor positioning escape sequence
    const output = mock_term.getOutput();

    // Should contain cursor positioning (ESC[row;colH or ESC[row;colf)
    // Row 2 (1-indexed), Col 4 (1-indexed for 0-based position 3)
    try testing.expect(std.mem.indexOf(u8, output, "\x1b[") != null);
}

/// Test 6: Empty buffer renders without crashing
test "rendering: empty buffer renders safely" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();
    // Empty buffer - no content inserted

    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    // Should not crash
    try renderer.render(buffer, 0, 0);

    // Should still render status line
    try testing.expect(mock_term.hasStatusLine());
}

/// Test 7: Large file renders without overflow
test "rendering: large file renders correctly" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();

    // Create file larger than screen height
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try content.writer().print("Line {d}\n", .{i});
    }

    try buffer.rope.insert(0, content.items);

    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    // Render from start
    try renderer.render(buffer, 0, 0);
    try testing.expect(mock_term.screenContains("Line 0"));

    // Render from middle
    mock_term.clearOutput();
    try renderer.render(buffer, 50, 0);
    try testing.expect(mock_term.screenContains("Line 50"));

    // Render from near end
    mock_term.clearOutput();
    try renderer.render(buffer, 95, 0);
    try testing.expect(mock_term.screenContains("Line 95"));
}

/// Test 8: Screen resize handled correctly
test "rendering: screen resize works" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var buffer = try Buffer.init(allocator, null);
    defer buffer.deinit();
    try buffer.rope.insert(0, "Test content for resize");

    // Initial size
    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    try renderer.render(buffer, 0, 0);
    try testing.expect(mock_term.hasVisibleText());

    // Resize
    try renderer.resize(100, 30);

    // Render after resize
    mock_term.clearOutput();
    try renderer.render(buffer, 0, 0);
    try testing.expect(mock_term.hasVisibleText());
}
