//! Fuzzy file finder for quick project navigation
//! Search and open files quickly using fuzzy matching

const std = @import("std");

/// File finder state
pub const FileFinder = struct {
    query: [256]u8 = undefined,
    query_len: usize = 0,
    selected_index: usize = 0,
    visible: bool = false,
    allocator: std.mem.Allocator,
    file_cache: std.ArrayList([]const u8),
    cache_valid: bool = false,

    pub fn init(allocator: std.mem.Allocator) FileFinder {
        return .{
            .allocator = allocator,
            .file_cache = std.ArrayList([]const u8).empty,
        };
    }

    pub fn deinit(self: *FileFinder) void {
        for (self.file_cache.items) |path| {
            self.allocator.free(path);
        }
        self.file_cache.deinit(self.allocator);
    }

    /// Show the file finder
    pub fn show(self: *FileFinder) void {
        self.visible = true;
        self.query_len = 0;
        self.selected_index = 0;
    }

    /// Hide the file finder
    pub fn hide(self: *FileFinder) void {
        self.visible = false;
        self.query_len = 0;
        self.selected_index = 0;
    }

    /// Add character to query
    pub fn addChar(self: *FileFinder, c: u21) !void {
        if (self.query_len >= self.query.len - 4) return error.QueryTooLong;

        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(c, &buf);

        for (buf[0..len]) |byte| {
            self.query[self.query_len] = byte;
            self.query_len += 1;
        }
        self.selected_index = 0; // Reset selection
    }

    /// Remove last character from query
    pub fn backspace(self: *FileFinder) void {
        if (self.query_len == 0) return;

        // UTF-8 aware backspace
        while (self.query_len > 0) {
            self.query_len -= 1;
            if (self.query_len == 0 or (self.query[self.query_len] & 0b11000000) != 0b10000000) {
                break;
            }
        }
        self.selected_index = 0;
    }

    /// Get current query string
    pub fn getQuery(self: *const FileFinder) []const u8 {
        return self.query[0..self.query_len];
    }

    /// Move selection up
    pub fn selectPrevious(self: *FileFinder) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    /// Move selection down
    pub fn selectNext(self: *FileFinder, max_items: usize) void {
        if (self.selected_index + 1 < max_items) {
            self.selected_index += 1;
        }
    }

    /// Scan directory for files and cache them
    pub fn scanDirectory(self: *FileFinder, path: []const u8) !void {
        // Clear existing cache
        for (self.file_cache.items) |cached_path| {
            self.allocator.free(cached_path);
        }
        self.file_cache.clearRetainingCapacity();

        // Recursively scan directory
        try self.scanDirectoryRecursive(path, path);
        self.cache_valid = true;
    }

    /// Recursive directory scanner
    fn scanDirectoryRecursive(self: *FileFinder, base_path: []const u8, current_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(current_path, .{ .iterate = true }) catch |err| {
            // Skip directories we can't open
            _ = err;
            return;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // Skip hidden files and directories
            if (entry.name[0] == '.') continue;

            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ current_path, entry.name });
            defer self.allocator.free(full_path);

            switch (entry.kind) {
                .file => {
                    // Store relative path
                    const relative = if (std.mem.eql(u8, base_path, current_path))
                        try self.allocator.dupe(u8, entry.name)
                    else
                        try std.fs.path.relative(self.allocator, base_path, full_path);

                    try self.file_cache.append(self.allocator, relative);
                },
                .directory => {
                    // Recursively scan subdirectory (skip common build/cache dirs)
                    if (std.mem.eql(u8, entry.name, "zig-cache") or
                        std.mem.eql(u8, entry.name, "zig-out") or
                        std.mem.eql(u8, entry.name, "node_modules") or
                        std.mem.eql(u8, entry.name, ".git"))
                    {
                        continue;
                    }

                    try self.scanDirectoryRecursive(base_path, full_path);
                },
                else => {},
            }
        }
    }

    /// Filter files based on query
    pub fn filterFiles(self: *const FileFinder, allocator: std.mem.Allocator) ![]FileMatch {
        var matches = std.ArrayList(FileMatch).empty;
        errdefer matches.deinit(allocator);

        const query = self.getQuery();

        // If no query, return all files
        if (query.len == 0) {
            for (self.file_cache.items) |path| {
                try matches.append(allocator, .{
                    .path = path,
                    .score = 0,
                });
            }
        } else {
            // Filter by fuzzy match
            for (self.file_cache.items) |path| {
                if (fuzzyMatch(query, path)) {
                    const score = fuzzyScore(query, path);
                    try matches.append(allocator, .{
                        .path = path,
                        .score = score,
                    });
                }
            }

            // Sort by score (descending)
            std.mem.sort(FileMatch, matches.items, {}, struct {
                fn lessThan(_: void, a: FileMatch, b: FileMatch) bool {
                    return a.score > b.score;
                }
            }.lessThan);
        }

        return matches.toOwnedSlice(allocator);
    }

    /// Invalidate file cache (call when files change)
    pub fn invalidateCache(self: *FileFinder) void {
        self.cache_valid = false;
    }
};

/// A file match with score
pub const FileMatch = struct {
    path: []const u8,
    score: usize,
};

/// Simple fuzzy matching - check if all query chars appear in order
fn fuzzyMatch(query: []const u8, text: []const u8) bool {
    if (query.len == 0) return true;

    var query_idx: usize = 0;
    for (text) |c| {
        if (query_idx >= query.len) break;

        const query_c = std.ascii.toLower(query[query_idx]);
        const text_c = std.ascii.toLower(c);

        if (query_c == text_c) {
            query_idx += 1;
        }
    }

    return query_idx == query.len;
}

/// Calculate fuzzy match score (higher is better)
fn fuzzyScore(query: []const u8, text: []const u8) usize {
    var score: usize = 0;
    var query_idx: usize = 0;
    var consecutive: usize = 0;

    // Bonus for matching filename vs full path
    const filename = std.fs.path.basename(text);
    const in_filename = fuzzyMatch(query, filename);
    if (in_filename) score += 100;

    for (text, 0..) |c, i| {
        if (query_idx >= query.len) break;

        const query_c = std.ascii.toLower(query[query_idx]);
        const text_c = std.ascii.toLower(c);

        if (query_c == text_c) {
            query_idx += 1;
            consecutive += 1;

            // Bonus for consecutive matches
            score += 10 + consecutive * 5;

            // Bonus for matching at start of path component
            if (i == 0 or text[i - 1] == std.fs.path.sep) {
                score += 30;
            }
        } else {
            consecutive = 0;
        }
    }

    return score;
}

// === Tests ===

test "file finder: fuzzy match" {
    try std.testing.expect(fuzzyMatch("test", "src/test.zig"));
    try std.testing.expect(fuzzyMatch("sted", "src/test/editor.zig"));
    try std.testing.expect(!fuzzyMatch("xyz", "src/test.zig"));
}

test "file finder: query handling" {
    const allocator = std.testing.allocator;
    var finder = FileFinder.init(allocator);
    defer finder.deinit();

    try finder.addChar('t');
    try finder.addChar('e');
    try finder.addChar('s');
    try finder.addChar('t');

    try std.testing.expectEqualStrings("test", finder.getQuery());

    finder.backspace();
    try std.testing.expectEqualStrings("tes", finder.getQuery());
}

test "file finder: show/hide" {
    const allocator = std.testing.allocator;
    var finder = FileFinder.init(allocator);
    defer finder.deinit();

    try std.testing.expect(!finder.visible);

    finder.show();
    try std.testing.expect(finder.visible);

    finder.hide();
    try std.testing.expect(!finder.visible);
}
