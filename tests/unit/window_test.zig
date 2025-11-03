//! Unit tests for Window management

const std = @import("std");
const testing = std.testing;
const Window = @import("../../src/editor/window.zig");

test "window: create single window" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const root_id = manager.root.getId();
    try testing.expect(root_id != 0);
}

test "window: split horizontal" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const original_id = manager.root.getId();

    // Split horizontally
    const split_result = try manager.splitWindow(original_id, .horizontal, 0.5);
    _ = split_result;

    // Root should now be a split node
    try testing.expect(manager.root.* == .split);
}

test "window: split vertical" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const original_id = manager.root.getId();

    // Split vertically
    const split_result = try manager.splitWindow(original_id, .vertical, 0.5);
    _ = split_result;

    try testing.expect(manager.root.* == .split);
}

test "window: get active window" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const active = manager.getActiveWindow();
    try testing.expect(active != null);
}

test "window: navigate to window" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const original_id = manager.root.getId();

    // Split to create multiple windows
    const result = try manager.splitWindow(original_id, .horizontal, 0.5);

    // Navigate to new window
    try manager.setActiveWindow(result.new_id);

    try testing.expectEqual(result.new_id, manager.active_window_id);
}

test "window: split ratio" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const original_id = manager.root.getId();

    // Split with 30/70 ratio
    _ = try manager.splitWindow(original_id, .horizontal, 0.3);

    // Verify split exists
    try testing.expect(manager.root.* == .split);
    if (manager.root.* == .split) {
        const split = manager.root.split;
        try testing.expectApproxEqAbs(@as(f32, 0.3), split.ratio, 0.01);
    }
}

test "window: close window in split" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const original_id = manager.root.getId();

    // Split to create two windows
    const result = try manager.splitWindow(original_id, .horizontal, 0.5);

    // Close one window
    try manager.closeWindow(result.new_id);

    // Should be back to single window
    try testing.expect(manager.root.* == .leaf);
}

test "window: cannot close only window" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const original_id = manager.root.getId();

    // Try to close the only window - should fail
    const result = manager.closeWindow(original_id);
    try testing.expectError(error.CannotCloseOnlyWindow, result);
}

test "window: resize split" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const original_id = manager.root.getId();

    // Create split
    _ = try manager.splitWindow(original_id, .horizontal, 0.5);

    // Resize split
    try manager.resizeSplit(original_id, 0.1); // Increase by 10%

    // Verify ratio changed
    if (manager.root.* == .split) {
        const split = manager.root.split;
        try testing.expect(split.ratio > 0.5);
    }
}

test "window: complex split layout" {
    const allocator = testing.allocator;
    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const root_id = manager.root.getId();

    // Create complex layout: split horizontally, then split right side vertically
    const h_result = try manager.splitWindow(root_id, .horizontal, 0.5);
    const v_result = try manager.splitWindow(h_result.new_id, .vertical, 0.5);
    _ = v_result;

    // Should have nested splits
    try testing.expect(manager.root.* == .split);
}
