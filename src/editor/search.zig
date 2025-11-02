//! Search functionality
//! Find text in buffer with navigation support

const std = @import("std");
const Cursor = @import("cursor.zig");

/// Search options
pub const SearchOptions = struct {
    case_sensitive: bool = true,
    whole_word: bool = false,
    wrap_around: bool = true,
};

/// Search state
pub const Search = struct {
    query: [128]u8 = undefined,
    query_len: usize = 0,
    replace_text: [128]u8 = undefined,
    replace_len: usize = 0,
    active: bool = false,
    incremental: bool = false, // If true, search updates as you type
    current_match: ?Match = null,
    match_count: usize = 0,
    match_index: usize = 0,
    replacements_made: usize = 0,
    options: SearchOptions = .{},
    history: std.ArrayList([]const u8),
    history_index: ?usize = null,
    max_history: usize = 50,
    allocator: std.mem.Allocator,

    pub const Match = struct {
        start: Cursor.Position,
        end: Cursor.Position,
    };

    pub fn init(allocator: std.mem.Allocator) Search {
        return .{
            .allocator = allocator,
            .history = std.ArrayList([]const u8).empty,
        };
    }

    pub fn deinit(self: *Search) void {
        // Free history entries
        for (self.history.items) |entry| {
            self.allocator.free(entry);
        }
        self.history.deinit(self.allocator);
    }

    /// Set search query
    pub fn setQuery(self: *Search, query: []const u8) !void {
        if (query.len > self.query.len) return error.QueryTooLong;
        @memcpy(self.query[0..query.len], query);
        self.query_len = query.len;
        self.active = query.len > 0;
    }

    /// Get current query
    pub fn getQuery(self: *const Search) []const u8 {
        return self.query[0..self.query_len];
    }

    /// Set replace text
    pub fn setReplaceText(self: *Search, text: []const u8) !void {
        if (text.len > self.replace_text.len) return error.ReplaceTooLong;
        @memcpy(self.replace_text[0..text.len], text);
        self.replace_len = text.len;
    }

    /// Get replace text
    pub fn getReplaceText(self: *const Search) []const u8 {
        return self.replace_text[0..self.replace_len];
    }

    /// Clear search
    pub fn clear(self: *Search) void {
        self.query_len = 0;
        self.replace_len = 0;
        self.active = false;
        self.incremental = false;
        self.current_match = null;
        self.match_count = 0;
        self.match_index = 0;
        self.replacements_made = 0;
    }

    /// Start incremental search
    pub fn startIncremental(self: *Search) void {
        self.clear();
        self.incremental = true;
        self.active = true;
    }

    /// Append character to search query (for incremental search)
    pub fn appendChar(self: *Search, c: u8) !void {
        if (self.query_len >= self.query.len) return error.QueryTooLong;
        self.query[self.query_len] = c;
        self.query_len += 1;
    }

    /// Remove last character from query (backspace in incremental search)
    pub fn backspace(self: *Search) void {
        if (self.query_len > 0) {
            self.query_len -= 1;
        }
    }

    /// Add query to history (avoid duplicates)
    pub fn addToHistory(self: *Search) !void {
        const query = self.getQuery();
        if (query.len == 0) return;

        // Check if already in history (most recent entries)
        for (self.history.items) |entry| {
            if (std.mem.eql(u8, entry, query)) {
                return; // Already in history, don't add duplicate
            }
        }

        // Add to history
        const query_copy = try self.allocator.dupe(u8, query);
        try self.history.append(self.allocator, query_copy);

        // Enforce max history size
        if (self.history.items.len > self.max_history) {
            const removed = self.history.orderedRemove(0);
            self.allocator.free(removed);
        }

        self.history_index = null; // Reset history navigation
    }

    /// Navigate to previous history item
    pub fn historyPrevious(self: *Search) void {
        if (self.history.items.len == 0) return;

        if (self.history_index) |idx| {
            if (idx > 0) {
                self.history_index = idx - 1;
            }
        } else {
            // Start from end
            self.history_index = self.history.items.len - 1;
        }

        if (self.history_index) |idx| {
            const entry = self.history.items[idx];
            const len = @min(entry.len, self.query.len);
            @memcpy(self.query[0..len], entry[0..len]);
            self.query_len = len;
        }
    }

    /// Navigate to next history item
    pub fn historyNext(self: *Search) void {
        if (self.history_index == null) return;

        const idx = self.history_index.?;
        if (idx + 1 < self.history.items.len) {
            self.history_index = idx + 1;
            const entry = self.history.items[idx + 1];
            const len = @min(entry.len, self.query.len);
            @memcpy(self.query[0..len], entry[0..len]);
            self.query_len = len;
        } else {
            // Back to current/empty
            self.history_index = null;
            self.query_len = 0;
        }
    }

    /// Toggle case sensitivity
    pub fn toggleCaseSensitive(self: *Search) void {
        self.options.case_sensitive = !self.options.case_sensitive;
    }

    /// Toggle whole word matching
    pub fn toggleWholeWord(self: *Search) void {
        self.options.whole_word = !self.options.whole_word;
    }

    /// Toggle wrap around
    pub fn toggleWrapAround(self: *Search) void {
        self.options.wrap_around = !self.options.wrap_around;
    }

    /// Get match statistics string
    pub fn getMatchInfo(self: *const Search) [64]u8 {
        var buf: [64]u8 = undefined;
        if (self.match_count == 0) {
            _ = std.fmt.bufPrint(&buf, "No matches", .{}) catch unreachable;
        } else {
            _ = std.fmt.bufPrint(&buf, "Match {d}/{d}", .{ self.match_index + 1, self.match_count }) catch unreachable;
        }
        return buf;
    }

    // === Helper Functions ===

    /// Check if character is a word boundary character
    fn isWordBoundary(c: u8) bool {
        return !((c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '_');
    }

    /// Check if match is at word boundary
    fn isAtWordBoundary(text: []const u8, offset: usize, len: usize) bool {
        // Check before match
        const before_is_boundary = (offset == 0) or isWordBoundary(text[offset - 1]);
        // Check after match
        const after_is_boundary = (offset + len >= text.len) or isWordBoundary(text[offset + len]);
        return before_is_boundary and after_is_boundary;
    }

    /// Check if query matches at given position with respect to search options
    fn matchesAt(self: *const Search, text: []const u8, offset: usize) bool {
        const query = self.getQuery();
        if (offset + query.len > text.len) return false;

        const slice = text[offset..offset + query.len];

        // Check match based on case sensitivity
        const matches = if (self.options.case_sensitive)
            std.mem.eql(u8, slice, query)
        else
            std.ascii.eqlIgnoreCase(slice, query);

        if (!matches) return false;

        // Check whole word if enabled
        if (self.options.whole_word) {
            return isAtWordBoundary(text, offset, query.len);
        }

        return true;
    }

    /// Find next match in text starting from position
    pub fn findNext(
        self: *Search,
        text: []const u8,
        start_pos: Cursor.Position,
    ) ?Match {
        if (self.query_len == 0) return null;

        const query = self.getQuery();

        // Convert position to byte offset
        var offset: usize = 0;
        var line: usize = 0;
        var col: usize = 0;

        while (offset < text.len) {
            if (line == start_pos.line and col >= start_pos.col) {
                // Start searching from here
                break;
            }
            if (text[offset] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
            offset += 1;
        }

        // Search for query
        while (offset < text.len) {
            if (offset + query.len > text.len) break;

            // Check if query matches at current position with options
            if (self.matchesAt(text, offset)) {
                // Found match - calculate position
                const match_start = Cursor.Position{ .line = line, .col = col };

                // Calculate end position
                var end_line = line;
                var end_col = col;
                for (query) |c| {
                    if (c == '\n') {
                        end_line += 1;
                        end_col = 0;
                    } else {
                        end_col += 1;
                    }
                }

                const match = Match{
                    .start = match_start,
                    .end = Cursor.Position{ .line = end_line, .col = end_col },
                };

                self.current_match = match;
                return match;
            }

            // Move to next position
            if (text[offset] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
            offset += 1;
        }

        return null;
    }

    /// Find previous match (search backwards)
    pub fn findPrevious(
        self: *Search,
        text: []const u8,
        start_pos: Cursor.Position,
    ) ?Match {
        if (self.query_len == 0) return null;

        const query = self.getQuery();

        // Build position-to-offset map by scanning text
        var positions = std.ArrayList(struct { line: usize, col: usize, offset: usize }).empty;
        defer positions.deinit(self.allocator);

        var line: usize = 0;
        var col: usize = 0;
        var offset: usize = 0;

        while (offset < text.len) : (offset += 1) {
            positions.append(self.allocator, .{
                .line = line,
                .col = col,
                .offset = offset,
            }) catch break;

            if (text[offset] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }

        // Search backwards
        var i: usize = positions.items.len;
        while (i > 0) {
            i -= 1;
            const pos = positions.items[i];

            // Skip positions at or after start_pos
            if (pos.line > start_pos.line or
                (pos.line == start_pos.line and pos.col >= start_pos.col)) {
                continue;
            }

            // Check if query matches at this position with options
            if (self.matchesAt(text, pos.offset)) {

                // Found match - calculate end position
                var end_line = pos.line;
                var end_col = pos.col;
                for (query) |c| {
                    if (c == '\n') {
                        end_line += 1;
                        end_col = 0;
                    } else {
                        end_col += 1;
                    }
                }

                const match = Match{
                    .start = Cursor.Position{ .line = pos.line, .col = pos.col },
                    .end = Cursor.Position{ .line = end_line, .col = end_col },
                };

                self.current_match = match;
                return match;
            }
        }

        return null;
    }

    /// Find all matches in text for highlighting
    pub fn findAll(
        self: *const Search,
        text: []const u8,
        allocator: std.mem.Allocator,
    ) ![]Match {
        if (self.query_len == 0) return &[_]Match{};

        const query = self.getQuery();
        var matches = std.ArrayList(Match).empty;
        errdefer matches.deinit(allocator);

        var line: usize = 0;
        var col: usize = 0;
        var offset: usize = 0;

        while (offset < text.len) {
            if (offset + query.len > text.len) break;

            // Check if query matches at current position with options
            if (self.matchesAt(text, offset)) {
                // Found match - calculate end position
                var end_line = line;
                var end_col = col;
                for (query) |c| {
                    if (c == '\n') {
                        end_line += 1;
                        end_col = 0;
                    } else {
                        end_col += 1;
                    }
                }

                const match = Match{
                    .start = Cursor.Position{ .line = line, .col = col },
                    .end = Cursor.Position{ .line = end_line, .col = end_col },
                };

                try matches.append(allocator, match);

                // Skip past this match
                offset += query.len;
                col = end_col;
                line = end_line;
                continue;
            }

            // Move to next position
            if (text[offset] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
            offset += 1;
        }

        return matches.toOwnedSlice(allocator);
    }

    /// Find all matches in text (for highlighting and count)
    pub fn findAllMatches(
        self: *Search,
        text: []const u8,
        allocator: std.mem.Allocator,
    ) ![]Match {
        if (self.query_len == 0) {
            return &[_]Match{};
        }

        const query = self.getQuery();
        var matches = std.ArrayList(Match).empty;
        errdefer matches.deinit(allocator);

        var offset: usize = 0;
        var line: usize = 0;
        var col: usize = 0;

        while (offset + query.len <= text.len) {
            // Check if query matches at current position with options
            if (self.matchesAt(text, offset)) {
                // Found match - calculate positions
                const match_start = Cursor.Position{ .line = line, .col = col };

                // Calculate end position
                var end_line = line;
                var end_col = col;
                for (query) |c| {
                    if (c == '\n') {
                        end_line += 1;
                        end_col = 0;
                    } else {
                        end_col += 1;
                    }
                }

                try matches.append(allocator, Match{
                    .start = match_start,
                    .end = Cursor.Position{ .line = end_line, .col = end_col },
                });

                // Skip past this match to find next one
                offset += query.len;
                col += query.len;
                continue;
            }

            // Move to next position
            if (text[offset] == '\n') {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
            offset += 1;
        }

        self.match_count = matches.items.len;
        return matches.toOwnedSlice(allocator);
    }

    /// Update match count for current query in text
    pub fn updateMatchCount(self: *Search, text: []const u8, allocator: std.mem.Allocator) !void {
        const matches = try self.findAllMatches(text, allocator);
        defer allocator.free(matches);
        // match_count is already set by findAllMatches
    }
};

// === Tests ===

test "search: basic find" {
    const allocator = std.testing.allocator;
    var search = Search.init(allocator);
    defer search.deinit();

    try search.setQuery("test");

    const text = "this is a test string";
    const match = search.findNext(text, .{ .line = 0, .col = 0 });

    try std.testing.expect(match != null);
    try std.testing.expectEqual(@as(usize, 0), match.?.start.line);
    try std.testing.expectEqual(@as(usize, 10), match.?.start.col);
}

test "search: no match" {
    const allocator = std.testing.allocator;
    var search = Search.init(allocator);
    defer search.deinit();

    try search.setQuery("xyz");

    const text = "this is a test string";
    const match = search.findNext(text, .{ .line = 0, .col = 0 });

    try std.testing.expect(match == null);
}
