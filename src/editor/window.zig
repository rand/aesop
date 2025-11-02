//! Window and pane management for split layouts
//! Implements a tree structure for recursive splits (VSCode/Vim-style)

const std = @import("std");
const Buffer = @import("../buffer/manager.zig");

/// Window ID type
pub const WindowId = u32;

/// Split direction
pub const SplitDirection = enum {
    horizontal, // Split top/bottom
    vertical,   // Split left/right
};

/// Window dimensions
pub const Dimensions = struct {
    row: u16,    // Top-left row
    col: u16,    // Top-left column
    height: u16, // Height in rows
    width: u16,  // Width in columns

    pub fn contains(self: Dimensions, row: u16, col: u16) bool {
        return row >= self.row and row < self.row + self.height and
            col >= self.col and col < self.col + self.width;
    }
};

/// Window node - can be a leaf (pane) or split container
pub const WindowNode = union(enum) {
    leaf: Leaf,
    split: Split,

    pub const Leaf = struct {
        id: WindowId,
        buffer_id: ?Buffer.BufferId,
        dimensions: Dimensions,
        scroll_offset: usize,
    };

    pub const Split = struct {
        id: WindowId,
        direction: SplitDirection,
        dimensions: Dimensions,
        split_ratio: f32, // 0.0 to 1.0, position of split
        left: *WindowNode,  // For horizontal: top, for vertical: left
        right: *WindowNode, // For horizontal: bottom, for vertical: right
    };

    pub fn getDimensions(self: *const WindowNode) Dimensions {
        return switch (self.*) {
            .leaf => |leaf| leaf.dimensions,
            .split => |split| split.dimensions,
        };
    }

    pub fn getId(self: *const WindowNode) WindowId {
        return switch (self.*) {
            .leaf => |leaf| leaf.id,
            .split => |split| split.id,
        };
    }

    /// Recursively free window tree
    pub fn deinit(self: *WindowNode, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .leaf => {},
            .split => |split| {
                split.left.deinit(allocator);
                split.right.deinit(allocator);
                allocator.destroy(split.left);
                allocator.destroy(split.right);
            },
        }
    }
};

/// Window manager - manages window splits and active window
pub const WindowManager = struct {
    root: *WindowNode,
    active_window_id: WindowId,
    next_id: WindowId,
    allocator: std.mem.Allocator,

    /// Initialize with single window
    pub fn init(allocator: std.mem.Allocator, dimensions: Dimensions) !WindowManager {
        const root = try allocator.create(WindowNode);
        root.* = WindowNode{
            .leaf = .{
                .id = 1,
                .buffer_id = null,
                .dimensions = dimensions,
                .scroll_offset = 0,
            },
        };

        return .{
            .root = root,
            .active_window_id = 1,
            .next_id = 2,
            .allocator = allocator,
        };
    }

    /// Clean up window manager
    pub fn deinit(self: *WindowManager) void {
        self.root.deinit(self.allocator);
        self.allocator.destroy(self.root);
    }

    /// Get active window node
    pub fn getActiveWindow(self: *WindowManager) ?*WindowNode.Leaf {
        return self.findLeaf(self.root, self.active_window_id);
    }

    /// Find leaf window by ID
    fn findLeaf(self: *WindowManager, node: *WindowNode, id: WindowId) ?*WindowNode.Leaf {
        return switch (node.*) {
            .leaf => |*leaf| if (leaf.id == id) leaf else null,
            .split => |split| blk: {
                if (self.findLeaf(split.left, id)) |found| {
                    break :blk found;
                }
                if (self.findLeaf(split.right, id)) |found| {
                    break :blk found;
                }
                break :blk null;
            },
        };
    }

    /// Split active window
    pub fn splitActive(self: *WindowManager, direction: SplitDirection, ratio: f32) !void {
        const active_id = self.active_window_id;
        try self.splitWindow(self.root, active_id, direction, ratio);
    }

    /// Split a specific window by ID
    fn splitWindow(
        self: *WindowManager,
        node: *WindowNode,
        target_id: WindowId,
        direction: SplitDirection,
        ratio: f32,
    ) !void {
        switch (node.*) {
            .leaf => |leaf| {
                if (leaf.id == target_id) {
                    // Replace this leaf with a split containing two new leaves
                    const old_dims = leaf.dimensions;

                    // Calculate dimensions for split children
                    const left_dims, const right_dims = calculateSplitDimensions(old_dims, direction, ratio);

                    // Create left child (reuse existing leaf data)
                    const left = try self.allocator.create(WindowNode);
                    left.* = WindowNode{
                        .leaf = .{
                            .id = leaf.id, // Keep original ID for left
                            .buffer_id = leaf.buffer_id,
                            .dimensions = left_dims,
                            .scroll_offset = leaf.scroll_offset,
                        },
                    };

                    // Create right child (new window)
                    const right = try self.allocator.create(WindowNode);
                    right.* = WindowNode{
                        .leaf = .{
                            .id = self.next_id,
                            .buffer_id = null,
                            .dimensions = right_dims,
                            .scroll_offset = 0,
                        },
                    };
                    const new_window_id = self.next_id;
                    self.next_id += 1;

                    // Replace leaf with split
                    node.* = WindowNode{
                        .split = .{
                            .id = self.next_id,
                            .direction = direction,
                            .dimensions = old_dims,
                            .split_ratio = ratio,
                            .left = left,
                            .right = right,
                        },
                    };
                    self.next_id += 1;

                    // Switch focus to new window
                    self.active_window_id = new_window_id;
                }
            },
            .split => |split| {
                // Recursively search for target window
                try self.splitWindow(split.left, target_id, direction, ratio);
                try self.splitWindow(split.right, target_id, direction, ratio);
            },
        }
    }

    /// Close active window (merge with sibling)
    pub fn closeActive(self: *WindowManager) !void {
        if (self.root.* == .leaf) {
            return error.CannotCloseOnlyWindow;
        }

        try self.closeWindow(self.root, self.active_window_id);
    }

    /// Close window and merge with sibling
    fn closeWindow(self: *WindowManager, node: *WindowNode, target_id: WindowId) !void {
        _ = self;
        _ = node;
        _ = target_id;
        // TODO: Implement window closing with sibling merge
        // This requires tracking parent-child relationships
        return error.NotImplemented;
    }

    /// Navigate to window in direction
    pub fn navigateDirection(self: *WindowManager, direction: SplitDirection, forward: bool) !void {
        _ = self;
        _ = direction;
        _ = forward;
        // TODO: Implement directional navigation
        return error.NotImplemented;
    }

    /// Resize active split
    pub fn resizeSplit(self: *WindowManager, delta: f32) !void {
        _ = self;
        _ = delta;
        // TODO: Implement split resizing
        return error.NotImplemented;
    }

    /// Get all visible windows (leaves)
    pub fn getVisibleWindows(self: *WindowManager, allocator: std.mem.Allocator) !std.ArrayList(*WindowNode.Leaf) {
        var windows = std.ArrayList(*WindowNode.Leaf).empty;
        try self.collectLeaves(self.root, &windows, allocator);
        return windows;
    }

    /// Recursively collect all leaf windows
    fn collectLeaves(
        self: *WindowManager,
        node: *WindowNode,
        list: *std.ArrayList(*WindowNode.Leaf),
        allocator: std.mem.Allocator,
    ) !void {
        switch (node.*) {
            .leaf => |*leaf| try list.append(allocator, leaf),
            .split => |split| {
                try self.collectLeaves(split.left, list, allocator);
                try self.collectLeaves(split.right, list, allocator);
            },
        }
    }
};

/// Calculate dimensions for split children
fn calculateSplitDimensions(
    parent: Dimensions,
    direction: SplitDirection,
    ratio: f32,
) struct { Dimensions, Dimensions } {
    const clamped_ratio = @max(0.1, @min(0.9, ratio)); // Clamp to 10-90%

    return switch (direction) {
        .horizontal => blk: {
            // Split top/bottom
            const top_height = @as(u16, @intFromFloat(@as(f32, @floatFromInt(parent.height)) * clamped_ratio));
            const bottom_height = parent.height - top_height;

            const top = Dimensions{
                .row = parent.row,
                .col = parent.col,
                .height = top_height,
                .width = parent.width,
            };

            const bottom = Dimensions{
                .row = parent.row + top_height,
                .col = parent.col,
                .height = bottom_height,
                .width = parent.width,
            };

            break :blk .{ top, bottom };
        },
        .vertical => blk: {
            // Split left/right
            const left_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(parent.width)) * clamped_ratio));
            const right_width = parent.width - left_width;

            const left = Dimensions{
                .row = parent.row,
                .col = parent.col,
                .height = parent.height,
                .width = left_width,
            };

            const right = Dimensions{
                .row = parent.row,
                .col = parent.col + left_width,
                .height = parent.height,
                .width = right_width,
            };

            break :blk .{ left, right };
        },
    };
}

// === Tests ===

test "window: init single window" {
    const allocator = std.testing.allocator;
    const dims = Dimensions{ .row = 0, .col = 0, .height = 24, .width = 80 };
    var manager = try WindowManager.init(allocator, dims);
    defer manager.deinit();

    try std.testing.expectEqual(@as(WindowId, 1), manager.active_window_id);
    try std.testing.expect(manager.root.* == .leaf);
}

test "window: split horizontal" {
    const allocator = std.testing.allocator;
    const dims = Dimensions{ .row = 0, .col = 0, .height = 24, .width = 80 };
    var manager = try WindowManager.init(allocator, dims);
    defer manager.deinit();

    try manager.splitActive(.horizontal, 0.5);

    try std.testing.expect(manager.root.* == .split);
    try std.testing.expectEqual(SplitDirection.horizontal, manager.root.split.direction);
}

test "window: split vertical" {
    const allocator = std.testing.allocator;
    const dims = Dimensions{ .row = 0, .col = 0, .height = 24, .width = 80 };
    var manager = try WindowManager.init(allocator, dims);
    defer manager.deinit();

    try manager.splitActive(.vertical, 0.5);

    try std.testing.expect(manager.root.* == .split);
    try std.testing.expectEqual(SplitDirection.vertical, manager.root.split.direction);
}

test "window: calculate split dimensions horizontal" {
    const parent = Dimensions{ .row = 0, .col = 0, .height = 24, .width = 80 };
    const top, const bottom = calculateSplitDimensions(parent, .horizontal, 0.5);

    try std.testing.expectEqual(@as(u16, 0), top.row);
    try std.testing.expectEqual(@as(u16, 12), top.height);

    try std.testing.expectEqual(@as(u16, 12), bottom.row);
    try std.testing.expectEqual(@as(u16, 12), bottom.height);
}

test "window: calculate split dimensions vertical" {
    const parent = Dimensions{ .row = 0, .col = 0, .height = 24, .width = 80 };
    const left, const right = calculateSplitDimensions(parent, .vertical, 0.5);

    try std.testing.expectEqual(@as(u16, 0), left.col);
    try std.testing.expectEqual(@as(u16, 40), left.width);

    try std.testing.expectEqual(@as(u16, 40), right.col);
    try std.testing.expectEqual(@as(u16, 40), right.width);
}

test "window: get visible windows" {
    const allocator = std.testing.allocator;
    const dims = Dimensions{ .row = 0, .col = 0, .height = 24, .width = 80 };
    var manager = try WindowManager.init(allocator, dims);
    defer manager.deinit();

    var windows = try manager.getVisibleWindows(allocator);
    defer windows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), windows.items.len);

    try manager.splitActive(.horizontal, 0.5);

    windows = try manager.getVisibleWindows(allocator);
    defer windows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), windows.items.len);
}
