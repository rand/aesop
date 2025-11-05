//! File tree browser for navigating project structure
//! Persistent sidebar showing directory hierarchy

const std = @import("std");

/// Tree node representing a file or directory
pub const TreeNode = struct {
    name: []const u8,
    path: []const u8,
    is_dir: bool,
    is_expanded: bool,
    depth: u8,
    children: std.ArrayList(*TreeNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8, is_dir: bool, depth: u8) !*TreeNode {
        const node = try allocator.create(TreeNode);
        node.* = .{
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .is_dir = is_dir,
            .is_expanded = false,
            .depth = depth,
            .children = std.ArrayList(*TreeNode).empty,
            .allocator = allocator,
        };
        return node;
    }

    pub fn deinit(self: *TreeNode) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit(self.allocator);
        self.allocator.free(self.name);
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }
};

/// File tree browser state
pub const FileTree = struct {
    visible: bool,
    root: ?*TreeNode,
    flat_view: std.ArrayList(*TreeNode),
    selected_index: usize,
    scroll_offset: usize,
    width: u16,
    allocator: std.mem.Allocator,
    cwd: [4096]u8, // Max path length
    cwd_len: usize,

    pub fn init(allocator: std.mem.Allocator) FileTree {
        return .{
            .visible = false,
            .root = null,
            .flat_view = std.ArrayList(*TreeNode).empty,
            .selected_index = 0,
            .scroll_offset = 0,
            .width = 30, // Default width
            .allocator = allocator,
            .cwd = undefined,
            .cwd_len = 0,
        };
    }

    pub fn deinit(self: *FileTree) void {
        if (self.root) |root| {
            root.deinit();
        }
        self.flat_view.deinit(self.allocator);
    }

    /// Show the file tree
    pub fn show(self: *FileTree) !void {
        self.visible = true;
        if (self.root == null) {
            try self.loadDirectory(".");
        }
    }

    /// Hide the file tree
    pub fn hide(self: *FileTree) void {
        self.visible = false;
    }

    /// Load directory tree starting from path
    pub fn loadDirectory(self: *FileTree, path: []const u8) !void {
        // Clear existing tree
        if (self.root) |root| {
            root.deinit();
        }
        self.flat_view.clearRetainingCapacity();

        // Get absolute path
        const abs_path = try std.fs.cwd().realpathAlloc(self.allocator, path);
        defer self.allocator.free(abs_path);

        @memcpy(self.cwd[0..abs_path.len], abs_path);
        self.cwd_len = abs_path.len;

        // Create root node
        const root_name = std.fs.path.basename(abs_path);
        self.root = try TreeNode.init(self.allocator, root_name, ".", true, 0);

        // Load immediate children
        try self.loadNodeChildren(self.root.?);

        // Expand root by default
        self.root.?.is_expanded = true;

        // Rebuild flat view
        try self.rebuildFlatView();

        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    /// Load children for a directory node
    fn loadNodeChildren(self: *FileTree, node: *TreeNode) !void {
        if (!node.is_dir) return;

        // Clear existing children
        for (node.children.items) |child| {
            child.deinit();
        }
        node.children.clearRetainingCapacity();

        // Open directory
        var dir = std.fs.cwd().openDir(node.path, .{ .iterate = true }) catch {
            // Can't open directory, skip
            return;
        };
        defer dir.close();

        // Collect entries
        var entries = std.ArrayList(std.fs.Dir.Entry).empty;
        defer entries.deinit(self.allocator);

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            // Skip entries with empty names (safety check)
            if (entry.name.len == 0) continue;

            // Skip ONLY "." and ".." special directories
            if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) {
                continue;
            }

            // Skip common build/cache directories (but show dotfiles like .gitignore)
            if (entry.kind == .directory) {
                if (std.mem.eql(u8, entry.name, "zig-cache") or
                    std.mem.eql(u8, entry.name, "zig-out") or
                    std.mem.eql(u8, entry.name, "node_modules") or
                    std.mem.eql(u8, entry.name, "target") or
                    std.mem.eql(u8, entry.name, "__pycache__") or
                    std.mem.eql(u8, entry.name, ".git")) // Hide .git directory (too large/not useful)
                {
                    continue;
                }
            }

            try entries.append(self.allocator, entry);
        }

        // Sort: directories first, then alphabetically
        std.mem.sort(std.fs.Dir.Entry, entries.items, {}, struct {
            fn lessThan(_: void, a: std.fs.Dir.Entry, b: std.fs.Dir.Entry) bool {
                // Directories come first
                if (a.kind == .directory and b.kind != .directory) return true;
                if (a.kind != .directory and b.kind == .directory) return false;
                // Then alphabetically
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);

        // Create child nodes
        for (entries.items) |entry| {
            // Build proper relative path
            // If parent is ".", child is just the name
            // Otherwise join parent path with child name
            const child_path = if (std.mem.eql(u8, node.path, "."))
                try self.allocator.dupe(u8, entry.name)
            else
                try std.fs.path.join(self.allocator, &[_][]const u8{ node.path, entry.name });
            defer self.allocator.free(child_path);

            const is_dir = entry.kind == .directory;
            const child = try TreeNode.init(
                self.allocator,
                entry.name,
                child_path,
                is_dir,
                node.depth + 1,
            );

            try node.children.append(self.allocator, child);
        }
    }

    /// Rebuild flat view from tree (for rendering)
    fn rebuildFlatView(self: *FileTree) !void {
        self.flat_view.clearRetainingCapacity();
        if (self.root) |root| {
            try self.addToFlatView(root);
        }
    }

    /// Recursively add node and its visible children to flat view
    fn addToFlatView(self: *FileTree, node: *TreeNode) !void {
        try self.flat_view.append(self.allocator, node);

        if (node.is_dir and node.is_expanded) {
            for (node.children.items) |child| {
                try self.addToFlatView(child);
            }
        }
    }

    /// Move selection up
    pub fn selectPrevious(self: *FileTree) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    /// Move selection down
    pub fn selectNext(self: *FileTree) void {
        if (self.selected_index + 1 < self.flat_view.items.len) {
            self.selected_index += 1;
        }
    }

    /// Toggle expand/collapse of selected directory
    pub fn toggleSelected(self: *FileTree) !void {
        if (self.selected_index >= self.flat_view.items.len) return;

        const node = self.flat_view.items[self.selected_index];
        if (!node.is_dir) return;

        if (node.is_expanded) {
            // Collapse
            node.is_expanded = false;
        } else {
            // Expand - load children if not loaded
            if (node.children.items.len == 0) {
                // Load children with error handling
                self.loadNodeChildren(node) catch |err| {
                    // If loading fails, don't expand the node
                    std.log.warn("Failed to load directory children: {}", .{err});
                    return;
                };
            }
            node.is_expanded = true;
        }

        // Rebuild flat view
        try self.rebuildFlatView();

        // Clamp selected_index to valid range after rebuild
        // (collapsing can make flat_view shorter, invalidating selected_index)
        if (self.flat_view.items.len > 0) {
            if (self.selected_index >= self.flat_view.items.len) {
                self.selected_index = self.flat_view.items.len - 1;
            }
        } else {
            self.selected_index = 0;
        }
    }

    /// Get selected node (for opening files)
    pub fn getSelected(self: *const FileTree) ?*TreeNode {
        if (self.selected_index >= self.flat_view.items.len) return null;
        return self.flat_view.items[self.selected_index];
    }

    /// Adjust scroll to keep selection visible
    pub fn adjustScroll(self: *FileTree, viewport_height: usize) void {
        if (self.selected_index < self.scroll_offset) {
            self.scroll_offset = self.selected_index;
        } else if (self.selected_index >= self.scroll_offset + viewport_height) {
            self.scroll_offset = self.selected_index - viewport_height + 1;
        }
    }
};
