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
    syntax_highlighting: bool = true,

    // Search settings
    search_case_sensitive: bool = false,
    search_wrap_around: bool = true,

    // Multi-cursor settings
    multi_cursor_enabled: bool = true,
    max_cursors: usize = 100,

    // Auto-pairing settings
    auto_pair_brackets: bool = true,

    // Performance settings
    scroll_offset: usize = 3, // Lines to keep above/below cursor
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

    /// Load configuration from file (simple key=value format)
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        var config = Config.init(allocator);

        // Try to open file, if it doesn't exist, return defaults
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return config; // Return defaults if file doesn't exist
            }
            return err;
        };
        defer file.close();

        // Read file contents
        const max_size = 1024 * 16; // 16KB max config file
        const contents = try file.readToEndAlloc(allocator, max_size);
        defer allocator.free(contents);

        // Parse line by line
        var lines = std.mem.splitSequence(u8, contents, "\n");
        while (lines.next()) |line| {
            // Skip empty lines and comments
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Parse key=value
            var parts = std.mem.splitSequence(u8, trimmed, "=");
            const key = parts.next() orelse continue;
            const value = parts.next() orelse continue;

            const key_trimmed = std.mem.trim(u8, key, " \t");
            const value_trimmed = std.mem.trim(u8, value, " \t");

            // Set config values based on key
            try config.parseKeyValue(key_trimmed, value_trimmed);
        }

        // Validate after loading
        try config.validate();

        return config;
    }

    /// Parse a single key=value pair
    fn parseKeyValue(self: *Config, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "tab_width")) {
            self.tab_width = try std.fmt.parseInt(u8, value, 10);
        } else if (std.mem.eql(u8, key, "expand_tabs")) {
            self.expand_tabs = try parseBool(value);
        } else if (std.mem.eql(u8, key, "line_numbers")) {
            self.line_numbers = try parseBool(value);
        } else if (std.mem.eql(u8, key, "relative_line_numbers")) {
            self.relative_line_numbers = try parseBool(value);
        } else if (std.mem.eql(u8, key, "auto_indent")) {
            self.auto_indent = try parseBool(value);
        } else if (std.mem.eql(u8, key, "wrap_lines")) {
            self.wrap_lines = try parseBool(value);
        } else if (std.mem.eql(u8, key, "show_whitespace")) {
            self.show_whitespace = try parseBool(value);
        } else if (std.mem.eql(u8, key, "highlight_current_line")) {
            self.highlight_current_line = try parseBool(value);
        } else if (std.mem.eql(u8, key, "show_indent_guides")) {
            self.show_indent_guides = try parseBool(value);
        } else if (std.mem.eql(u8, key, "syntax_highlighting")) {
            self.syntax_highlighting = try parseBool(value);
        } else if (std.mem.eql(u8, key, "search_case_sensitive")) {
            self.search_case_sensitive = try parseBool(value);
        } else if (std.mem.eql(u8, key, "search_wrap_around")) {
            self.search_wrap_around = try parseBool(value);
        } else if (std.mem.eql(u8, key, "multi_cursor_enabled")) {
            self.multi_cursor_enabled = try parseBool(value);
        } else if (std.mem.eql(u8, key, "max_cursors")) {
            self.max_cursors = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "auto_pair_brackets")) {
            self.auto_pair_brackets = try parseBool(value);
        } else if (std.mem.eql(u8, key, "scroll_offset")) {
            self.scroll_offset = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "max_undo_history")) {
            self.max_undo_history = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "auto_save")) {
            self.auto_save = try parseBool(value);
        } else if (std.mem.eql(u8, key, "auto_save_delay_ms")) {
            self.auto_save_delay_ms = try std.fmt.parseInt(u64, value, 10);
        } else if (std.mem.eql(u8, key, "trim_trailing_whitespace")) {
            self.trim_trailing_whitespace = try parseBool(value);
        } else if (std.mem.eql(u8, key, "ensure_newline_at_eof")) {
            self.ensure_newline_at_eof = try parseBool(value);
        }
        // Unknown keys are silently ignored
    }

    /// Save configuration to file (simple key=value format)
    pub fn saveToFile(self: *const Config, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var writer = file.writer();

        try writer.writeAll("# Aesop Editor Configuration\n");
        try writer.writeAll("# Edit this file to customize your editor settings\n\n");

        try writer.writeAll("# Editor behavior\n");
        try writer.print("tab_width={d}\n", .{self.tab_width});
        try writer.print("expand_tabs={s}\n", .{if (self.expand_tabs) "true" else "false"});
        try writer.print("line_numbers={s}\n", .{if (self.line_numbers) "true" else "false"});
        try writer.print("relative_line_numbers={s}\n", .{if (self.relative_line_numbers) "true" else "false"});
        try writer.print("auto_indent={s}\n", .{if (self.auto_indent) "true" else "false"});
        try writer.print("wrap_lines={s}\n\n", .{if (self.wrap_lines) "true" else "false"});

        try writer.writeAll("# Visual settings\n");
        try writer.print("show_whitespace={s}\n", .{if (self.show_whitespace) "true" else "false"});
        try writer.print("highlight_current_line={s}\n", .{if (self.highlight_current_line) "true" else "false"});
        try writer.print("show_indent_guides={s}\n", .{if (self.show_indent_guides) "true" else "false"});
        try writer.print("syntax_highlighting={s}\n\n", .{if (self.syntax_highlighting) "true" else "false"});

        try writer.writeAll("# Search settings\n");
        try writer.print("search_case_sensitive={s}\n", .{if (self.search_case_sensitive) "true" else "false"});
        try writer.print("search_wrap_around={s}\n\n", .{if (self.search_wrap_around) "true" else "false"});

        try writer.writeAll("# Multi-cursor settings\n");
        try writer.print("multi_cursor_enabled={s}\n", .{if (self.multi_cursor_enabled) "true" else "false"});
        try writer.print("max_cursors={d}\n\n", .{self.max_cursors});

        try writer.writeAll("# Auto-pairing settings\n");
        try writer.print("auto_pair_brackets={s}\n\n", .{if (self.auto_pair_brackets) "true" else "false"});

        try writer.writeAll("# Performance settings\n");
        try writer.print("scroll_offset={d}\n", .{self.scroll_offset});
        try writer.print("max_undo_history={d}\n\n", .{self.max_undo_history});

        try writer.writeAll("# File handling\n");
        try writer.print("auto_save={s}\n", .{if (self.auto_save) "true" else "false"});
        try writer.print("auto_save_delay_ms={d}\n", .{self.auto_save_delay_ms});
        try writer.print("trim_trailing_whitespace={s}\n", .{if (self.trim_trailing_whitespace) "true" else "false"});
        try writer.print("ensure_newline_at_eof={s}\n", .{if (self.ensure_newline_at_eof) "true" else "false"});
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

/// Parse boolean from string
fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "yes")) {
        return true;
    } else if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "no")) {
        return false;
    }
    return error.InvalidBoolean;
}

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

test "config: parse bool" {
    try std.testing.expectEqual(true, try parseBool("true"));
    try std.testing.expectEqual(true, try parseBool("1"));
    try std.testing.expectEqual(true, try parseBool("yes"));
    try std.testing.expectEqual(false, try parseBool("false"));
    try std.testing.expectEqual(false, try parseBool("0"));
    try std.testing.expectEqual(false, try parseBool("no"));
    try std.testing.expectError(error.InvalidBoolean, parseBool("maybe"));
}

test "config: load from missing file" {
    const allocator = std.testing.allocator;
    const config = try Config.loadFromFile(allocator, "/nonexistent/path.conf");
    defer config.deinit();

    // Should return defaults
    try std.testing.expectEqual(@as(u8, 4), config.tab_width);
    try std.testing.expectEqual(true, config.expand_tabs);
}
