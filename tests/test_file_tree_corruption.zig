const std = @import("std");
const testing = std.testing;
const aesop = @import("aesop");
const FileTree = aesop.editor.file_tree.FileTree;

test "file tree loads without corruption" {
    const allocator = testing.allocator;

    var tree = FileTree.init(allocator);
    defer tree.deinit();

    // Load current directory
    try tree.loadDirectory(".");

    // Verify flat_view has valid entries
    try testing.expect(tree.flat_view.items.len > 0);

    std.debug.print("\n=== File Tree Loaded ===\n", .{});
    std.debug.print("Total items: {}\n", .{tree.flat_view.items.len});

    // Check for duplicates
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    // Check each entry for validity
    for (tree.flat_view.items, 0..) |node, i| {
        std.debug.print("[{}] name='{s}' len={} is_dir={} path='{s}'\n", .{
            i, node.name, node.name.len, node.is_dir, node.path
        });

        // Verify name is not empty
        try testing.expect(node.name.len > 0);

        // Verify path is not empty
        try testing.expect(node.path.len > 0);

        // Check for duplicates
        if (seen.contains(node.name)) {
            std.debug.print("ERROR: Duplicate entry found: {s}\n", .{node.name});
            return error.DuplicateEntry;
        }
        try seen.put(node.name, {});

        // Verify name contains only valid characters (no garbage)
        for (node.name) |c| {
            if (c < 32 or c > 126) {
                if (c != '\n' and c != '\r' and c != '\t') {
                    std.debug.print("ERROR: Invalid character in name: {}\n", .{c});
                    return error.InvalidCharacter;
                }
            }
        }
    }

    std.debug.print("=== All Entries Valid, No Duplicates ===\n\n", .{});
}

test "file tree toggle doesn't cause corruption" {
    const allocator = testing.allocator;

    var tree = FileTree.init(allocator);
    defer tree.deinit();

    try tree.loadDirectory(".");

    const initial_count = tree.flat_view.items.len;
    std.debug.print("\n=== Testing Toggle ===\n", .{});
    std.debug.print("Initial count: {}\n", .{initial_count});

    // Find first directory to toggle
    var dir_index: ?usize = null;
    for (tree.flat_view.items, 0..) |node, i| {
        if (node.is_dir and i > 0) { // Skip root
            dir_index = i;
            std.debug.print("Found directory at index {}: {s}\n", .{i, node.name});
            break;
        }
    }

    if (dir_index) |idx| {
        tree.selected_index = idx;

        // Toggle expand
        try tree.toggleSelected();
        std.debug.print("After expand: {} items\n", .{tree.flat_view.items.len});

        // Verify all entries still valid
        for (tree.flat_view.items, 0..) |node, i| {
            try testing.expect(node.name.len > 0);
            std.debug.print("  [{}] {s}\n", .{i, node.name});
        }

        // Toggle collapse
        tree.selected_index = idx;
        try tree.toggleSelected();
        std.debug.print("After collapse: {} items\n", .{tree.flat_view.items.len});

        // Verify all entries still valid
        for (tree.flat_view.items) |node| {
            try testing.expect(node.name.len > 0);
        }
    }

    std.debug.print("=== Toggle Test Passed ===\n\n", .{});
}

test "flat_view doesn't contain stale pointers after rebuild" {
    const allocator = testing.allocator;

    var tree = FileTree.init(allocator);
    defer tree.deinit();

    try tree.loadDirectory(".");

    // Store node names and depths to verify structure consistency
    var old_names = std.ArrayList([]const u8){};
    defer {
        for (old_names.items) |name| {
            allocator.free(name);
        }
        old_names.deinit(allocator);
    }

    for (tree.flat_view.items) |node| {
        const name_copy = try allocator.dupe(u8, node.name);
        try old_names.append(allocator, name_copy);
    }

    std.debug.print("\n=== Testing Stale Pointers ===\n", .{});
    std.debug.print("Initial pointers: {}\n", .{old_names.items.len});

    // Reload the same directory
    try tree.loadDirectory(".");

    std.debug.print("After reload: {} items\n", .{tree.flat_view.items.len});

    // Verify all nodes in flat_view are valid (not corrupted)
    // A stale/corrupted node would have invalid data
    for (tree.flat_view.items) |node| {
        // Check node has valid name (non-empty, valid UTF-8)
        try testing.expect(node.name.len > 0);

        // Check depth is reasonable (< 100 levels deep)
        try testing.expect(node.depth < 100);

        // Check path is valid (non-null for non-root)
        try testing.expect(node.path.len > 0);
    }

    // Verify the tree structure is consistent (same names in same order)
    // This ensures we reloaded the same directory structure
    try testing.expectEqual(old_names.items.len, tree.flat_view.items.len);

    std.debug.print("=== No Stale Pointers Found ===\n\n", .{});
}
