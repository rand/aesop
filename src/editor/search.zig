//! Search functionality
//! Find text in buffer with navigation support

const std = @import("std");
const Cursor = @import("cursor.zig");

/// Search state
pub const Search = struct {
    query: [128]u8 = undefined,
    query_len: usize = 0,
    active: bool = false,
    incremental: bool = false, // If true, search updates as you type
    current_match: ?Match = null,
    match_count: usize = 0,
    match_index: usize = 0,
    allocator: std.mem.Allocator,

    pub const Match = struct {
        start: Cursor.Position,
        end: Cursor.Position,
    };

    pub fn init(allocator: std.mem.Allocator) Search {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Search) void {
        _ = self;
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

    /// Clear search
    pub fn clear(self: *Search) void {
        self.query_len = 0;
        self.active = false;
        self.incremental = false;
        self.current_match = null;
        self.match_count = 0;
        self.match_index = 0;
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

            // Check if query matches at current position
            if (std.mem.eql(u8, text[offset..offset + query.len], query)) {
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

            // Check if query matches at this position
            if (pos.offset + query.len <= text.len and
                std.mem.eql(u8, text[pos.offset..pos.offset + query.len], query)) {

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

            // Check if query matches at current position
            if (std.mem.eql(u8, text[offset..offset + query.len], query)) {
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
