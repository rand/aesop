//! Code completion UI component
//! Displays completion suggestions from LSP or other sources

const std = @import("std");

/// Completion item from LSP or other source
pub const CompletionItem = struct {
    label: []const u8, // Main text to display
    kind: CompletionKind, // Type of completion (function, variable, etc.)
    detail: ?[]const u8 = null, // Additional info (signature, type)
    documentation: ?[]const u8 = null, // Documentation string
    insert_text: ?[]const u8 = null, // Text to insert (defaults to label)
    sort_text: ?[]const u8 = null, // Text used for sorting

    pub fn deinit(self: *CompletionItem, allocator: std.mem.Allocator) void {
        allocator.free(self.label);
        if (self.detail) |detail| allocator.free(detail);
        if (self.documentation) |doc| allocator.free(doc);
        if (self.insert_text) |text| allocator.free(text);
        if (self.sort_text) |text| allocator.free(text);
    }
};

/// LSP completion kinds (subset of LSP spec)
pub const CompletionKind = enum(u8) {
    text = 1,
    method = 2,
    function = 3,
    constructor = 4,
    field = 5,
    variable = 6,
    class = 7,
    interface = 8,
    module = 9,
    property = 10,
    unit = 11,
    value = 12,
    enum_type = 13,
    keyword = 14,
    snippet = 15,
    color = 16,
    file = 17,
    reference = 18,
    folder = 19,
    enum_member = 20,
    constant = 21,
    struct_type = 22,
    event = 23,
    operator = 24,
    type_parameter = 25,

    /// Get icon/symbol for completion kind
    pub fn icon(self: CompletionKind) []const u8 {
        return switch (self) {
            .text => "T",
            .method => "m",
            .function => "f",
            .constructor => "C",
            .field => "F",
            .variable => "v",
            .class => "c",
            .interface => "i",
            .module => "M",
            .property => "p",
            .unit => "U",
            .value => "V",
            .enum_type => "E",
            .keyword => "k",
            .snippet => "S",
            .color => "#",
            .file => "F",
            .reference => "r",
            .folder => "D",
            .enum_member => "e",
            .constant => "C",
            .struct_type => "s",
            .event => "E",
            .operator => "o",
            .type_parameter => "t",
        };
    }
};

/// Completion list state
pub const CompletionList = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(CompletionItem),
    filtered_indices: std.ArrayList(usize), // Indices into items array after filtering
    selected_index: usize, // Index into filtered_indices
    visible: bool,
    trigger_pos: Position, // Position where completion was triggered
    filter_query: [64]u8, // Characters typed since trigger
    filter_len: usize,

    pub const Position = struct {
        line: usize,
        col: usize,
    };

    pub fn init(allocator: std.mem.Allocator) CompletionList {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(CompletionItem).empty,
            .filtered_indices = std.ArrayList(usize).empty,
            .selected_index = 0,
            .visible = false,
            .trigger_pos = .{ .line = 0, .col = 0 },
            .filter_query = undefined,
            .filter_len = 0,
        };
    }

    pub fn deinit(self: *CompletionList) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
    }

    /// Show completion list at cursor position
    pub fn show(self: *CompletionList, line: usize, col: usize) void {
        self.visible = true;
        self.selected_index = 0;
        self.trigger_pos = .{ .line = line, .col = col };
        self.filter_len = 0;
    }

    /// Hide completion list
    pub fn hide(self: *CompletionList) void {
        self.visible = false;
        self.selected_index = 0;
        self.filter_len = 0;
    }

    /// Clear all completion items
    pub fn clear(self: *CompletionList) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();
        self.filtered_indices.clearRetainingCapacity();
        self.selected_index = 0;
    }

    /// Set completion items (takes ownership)
    pub fn setItems(self: *CompletionList, items: []CompletionItem) !void {
        self.clear();
        try self.items.ensureTotalCapacity(self.allocator, items.len);
        for (items) |item| {
            try self.items.append(self.allocator, item);
        }
        try self.rebuildFilteredIndices();
    }

    /// Add a single completion item
    pub fn addItem(self: *CompletionList, item: CompletionItem) !void {
        try self.items.append(self.allocator, item);
        try self.rebuildFilteredIndices();
    }

    /// Add character to filter query and refilter
    pub fn addFilterChar(self: *CompletionList, c: u21) !void {
        if (self.filter_len >= self.filter_query.len - 4) return error.FilterTooLong;

        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(c, &buf);

        for (buf[0..len]) |byte| {
            self.filter_query[self.filter_len] = byte;
            self.filter_len += 1;
        }

        try self.rebuildFilteredIndices();
        self.selected_index = 0;
    }

    /// Remove last character from filter query
    pub fn backspaceFilter(self: *CompletionList) !void {
        if (self.filter_len == 0) return;

        // UTF-8 aware backspace
        while (self.filter_len > 0) {
            self.filter_len -= 1;
            if (self.filter_len == 0 or (self.filter_query[self.filter_len] & 0b11000000) != 0b10000000) {
                break;
            }
        }

        try self.rebuildFilteredIndices();
        self.selected_index = 0;
    }

    /// Get current filter query
    pub fn getFilter(self: *const CompletionList) []const u8 {
        return self.filter_query[0..self.filter_len];
    }

    /// Rebuild filtered indices based on current filter
    fn rebuildFilteredIndices(self: *CompletionList) !void {
        self.filtered_indices.clearRetainingCapacity();

        const filter = self.getFilter();
        if (filter.len == 0) {
            // No filter - show all items
            for (0..self.items.items.len) |i| {
                try self.filtered_indices.append(self.allocator, i);
            }
        } else {
            // Filter items by prefix match
            for (self.items.items, 0..) |item, i| {
                if (std.ascii.startsWithIgnoreCase(item.label, filter)) {
                    try self.filtered_indices.append(self.allocator, i);
                }
            }
        }
    }

    /// Move selection up
    pub fn selectPrevious(self: *CompletionList) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    /// Move selection down
    pub fn selectNext(self: *CompletionList) void {
        if (self.selected_index + 1 < self.filtered_indices.items.len) {
            self.selected_index += 1;
        }
    }

    /// Get currently selected item (or null if none)
    pub fn getSelectedItem(self: *const CompletionList) ?*const CompletionItem {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_index >= self.filtered_indices.items.len) return null;

        const item_index = self.filtered_indices.items[self.selected_index];
        return &self.items.items[item_index];
    }

    /// Get filtered items for rendering
    pub fn getFilteredItems(self: *const CompletionList) []const CompletionItem {
        // This would need to return a slice based on filtered_indices
        // For now, simplified version
        return self.items.items;
    }

    /// Get number of filtered items
    pub fn getFilteredCount(self: *const CompletionList) usize {
        return self.filtered_indices.items.len;
    }
};

// === Tests ===

test "completion: init and deinit" {
    const allocator = std.testing.allocator;
    var list = CompletionList.init(allocator);
    defer list.deinit();

    try std.testing.expect(!list.visible);
    try std.testing.expectEqual(@as(usize, 0), list.items.items.len);
}

test "completion: show and hide" {
    const allocator = std.testing.allocator;
    var list = CompletionList.init(allocator);
    defer list.deinit();

    list.show(10, 5);
    try std.testing.expect(list.visible);
    try std.testing.expectEqual(@as(usize, 10), list.trigger_pos.line);
    try std.testing.expectEqual(@as(usize, 5), list.trigger_pos.col);

    list.hide();
    try std.testing.expect(!list.visible);
}

test "completion: add items and filter" {
    const allocator = std.testing.allocator;
    var list = CompletionList.init(allocator);
    defer list.deinit();

    // Add items
    try list.addItem(.{
        .label = try allocator.dupe(u8, "function"),
        .kind = .function,
    });
    try list.addItem(.{
        .label = try allocator.dupe(u8, "field"),
        .kind = .field,
    });
    try list.addItem(.{
        .label = try allocator.dupe(u8, "foo"),
        .kind = .variable,
    });

    try std.testing.expectEqual(@as(usize, 3), list.items.items.len);
    try std.testing.expectEqual(@as(usize, 3), list.getFilteredCount());

    // Filter by 'f'
    try list.addFilterChar('f');
    try std.testing.expectEqual(@as(usize, 3), list.getFilteredCount()); // function, field, foo

    // Filter by 'fu'
    try list.addFilterChar('u');
    try std.testing.expectEqual(@as(usize, 1), list.getFilteredCount()); // function
}

test "completion: selection navigation" {
    const allocator = std.testing.allocator;
    var list = CompletionList.init(allocator);
    defer list.deinit();

    try list.addItem(.{
        .label = try allocator.dupe(u8, "item1"),
        .kind = .variable,
    });
    try list.addItem(.{
        .label = try allocator.dupe(u8, "item2"),
        .kind = .variable,
    });

    try std.testing.expectEqual(@as(usize, 0), list.selected_index);

    list.selectNext();
    try std.testing.expectEqual(@as(usize, 1), list.selected_index);

    list.selectNext(); // Should not go past end
    try std.testing.expectEqual(@as(usize, 1), list.selected_index);

    list.selectPrevious();
    try std.testing.expectEqual(@as(usize, 0), list.selected_index);

    list.selectPrevious(); // Should not go negative
    try std.testing.expectEqual(@as(usize, 0), list.selected_index);
}
