//! Configuration system for editor settings
//! Provides typed access to user preferences with sensible defaults

const std = @import("std");

/// Editor configuration
pub const Config = struct {
    // Editor behavior
    tab_width: u8 = 4,
    expand_tabs: bool = true,
    line_numbers: bool = true,
    relative_line_numbers: bool = false,
    auto_indent: bool = true,
    wrap_lines: bool = false,

    // Visual settings
    show_whitespace: bool = false,
    highlight_current_line: bool = true,
    show_indent_guides: bool = false,

    // Search settings
    search_case_sensitive: bool = false,
    search_wrap_around: bool = true,

    // Multi-cursor settings
    multi_cursor_enabled: bool = true,
    max_cursors: usize = 100,

    // Performance settings
    scroll_offset: usize = 3,  // Lines to keep above/below cursor
    max_undo_history: usize = 1000,

    // File handling
    auto_save: bool = false,
    auto_save_delay_ms: u64 = 1000,
    trim_trailing_whitespace: bool = false,
    ensure_newline_at_eof: bool = true,

    allocator: std.mem.Allocator,

    /// Initialize with default configuration
    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .allocator = allocator,
        };
    }

    /// Clean up configuration
    pub fn deinit(self: *Config) void {
        _ = self;
    }

    /// Load configuration from file
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        _ = path;
        // TODO: Implement file loading (TOML or JSON)
        // For now, return defaults
        return Config.init(allocator);
    }

    /// Save configuration to file
    pub fn saveToFile(self: *const Config, path: []const u8) !void {
        _ = self;
        _ = path;
        // TODO: Implement file saving
    }

    /// Validate configuration values
    pub fn validate(self: *const Config) !void {
        if (self.tab_width == 0 or self.tab_width > 16) {
            return error.InvalidTabWidth;
        }

        if (self.max_cursors == 0 or self.max_cursors > 1000) {
            return error.InvalidMaxCursors;
        }

        if (self.max_undo_history == 0) {
            return error.InvalidUndoHistory;
        }
    }

    /// Get tab string (spaces or tab character based on expand_tabs)
    pub fn getTabString(self: *const Config, allocator: std.mem.Allocator) ![]const u8 {
        if (self.expand_tabs) {
            const spaces = try allocator.alloc(u8, self.tab_width);
            @memset(spaces, ' ');
            return spaces;
        } else {
            const tab = try allocator.alloc(u8, 1);
            tab[0] = '\t';
            return tab;
        }
    }

    /// Check if cursor should be centered
    pub fn shouldCenterCursor(self: *const Config, cursor_line: usize, viewport_start: usize, viewport_height: usize) bool {
        const distance_from_top = cursor_line -| viewport_start;
        const distance_from_bottom = (viewport_start + viewport_height) -| cursor_line;

        return distance_from_top < self.scroll_offset or distance_from_bottom < self.scroll_offset;
    }
};

/// Configuration builder for fluent API
pub const ConfigBuilder = struct {
    config: Config,

    pub fn init(allocator: std.mem.Allocator) ConfigBuilder {
        return .{
            .config = Config.init(allocator),
        };
    }

    pub fn tabWidth(self: *ConfigBuilder, width: u8) *ConfigBuilder {
        self.config.tab_width = width;
        return self;
    }

    pub fn expandTabs(self: *ConfigBuilder, expand: bool) *ConfigBuilder {
        self.config.expand_tabs = expand;
        return self;
    }

    pub fn lineNumbers(self: *ConfigBuilder, show: bool) *ConfigBuilder {
        self.config.line_numbers = show;
        return self;
    }

    pub fn relativeLineNumbers(self: *ConfigBuilder, show: bool) *ConfigBuilder {
        self.config.relative_line_numbers = show;
        return self;
    }

    pub fn autoIndent(self: *ConfigBuilder, enabled: bool) *ConfigBuilder {
        self.config.auto_indent = enabled;
        return self;
    }

    pub fn searchCaseSensitive(self: *ConfigBuilder, sensitive: bool) *ConfigBuilder {
        self.config.search_case_sensitive = sensitive;
        return self;
    }

    pub fn maxCursors(self: *ConfigBuilder, max: usize) *ConfigBuilder {
        self.config.max_cursors = max;
        return self;
    }

    pub fn scrollOffset(self: *ConfigBuilder, offset: usize) *ConfigBuilder {
        self.config.scroll_offset = offset;
        return self;
    }

    pub fn build(self: *ConfigBuilder) !Config {
        try self.config.validate();
        return self.config;
    }
};

// === Tests ===

test "config: default values" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    try std.testing.expectEqual(@as(u8, 4), config.tab_width);
    try std.testing.expectEqual(true, config.expand_tabs);
    try std.testing.expectEqual(true, config.line_numbers);
}

test "config: validation" {
    const allocator = std.testing.allocator;

    // Valid config
    var config = Config.init(allocator);
    defer config.deinit();
    try config.validate();

    // Invalid tab width
    config.tab_width = 0;
    try std.testing.expectError(error.InvalidTabWidth, config.validate());

    config.tab_width = 20;
    try std.testing.expectError(error.InvalidTabWidth, config.validate());
}

test "config: builder" {
    const allocator = std.testing.allocator;
    var builder = ConfigBuilder.init(allocator);

    var config = try builder
        .tabWidth(2)
        .expandTabs(false)
        .lineNumbers(true)
        .maxCursors(50)
        .build();
    defer config.deinit();

    try std.testing.expectEqual(@as(u8, 2), config.tab_width);
    try std.testing.expectEqual(false, config.expand_tabs);
    try std.testing.expectEqual(@as(usize, 50), config.max_cursors);
}

test "config: get tab string" {
    const allocator = std.testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    // Spaces mode
    config.expand_tabs = true;
    config.tab_width = 4;
    const spaces = try config.getTabString(allocator);
    defer allocator.free(spaces);
    try std.testing.expectEqualStrings("    ", spaces);

    // Tab mode
    config.expand_tabs = false;
    const tab = try config.getTabString(allocator);
    defer allocator.free(tab);
    try std.testing.expectEqualStrings("\t", tab);
}
