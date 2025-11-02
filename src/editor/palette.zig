//! Command palette for discovering and executing commands
//! Fuzzy search through available commands with descriptions

const std = @import("std");
const Command = @import("command.zig");

/// Command palette state
pub const Palette = struct {
    query: [128]u8 = undefined,
    query_len: usize = 0,
    selected_index: usize = 0,
    visible: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Palette {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Palette) void {
        _ = self;
    }

    /// Show the palette
    pub fn show(self: *Palette) void {
        self.visible = true;
        self.query_len = 0;
        self.selected_index = 0;
    }

    /// Hide the palette
    pub fn hide(self: *Palette) void {
        self.visible = false;
        self.query_len = 0;
        self.selected_index = 0;
    }

    /// Add character to query
    pub fn addChar(self: *Palette, c: u21) !void {
        if (self.query_len >= self.query.len - 4) return error.QueryTooLong;

        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(c, &buf);

        // Copy to query
        for (buf[0..len]) |byte| {
            self.query[self.query_len] = byte;
            self.query_len += 1;
        }
    }

    /// Remove last character from query
    pub fn backspace(self: *Palette) void {
        if (self.query_len == 0) return;

        // UTF-8 aware backspace - remove last codepoint
        while (self.query_len > 0) {
            self.query_len -= 1;
            // Check if we're at the start of a UTF-8 codepoint
            if (self.query_len == 0 or (self.query[self.query_len] & 0b11000000) != 0b10000000) {
                break;
            }
        }
        self.selected_index = 0; // Reset selection
    }

    /// Get current query string
    pub fn getQuery(self: *const Palette) []const u8 {
        return self.query[0..self.query_len];
    }

    /// Move selection up
    pub fn selectPrevious(self: *Palette) void {
        if (self.selected_index > 0) {
            self.selected_index -= 1;
        }
    }

    /// Move selection down
    pub fn selectNext(self: *Palette, max_items: usize) void {
        if (self.selected_index + 1 < max_items) {
            self.selected_index += 1;
        }
    }

    /// Filter commands based on query
    pub fn filterCommands(
        self: *const Palette,
        registry: *const Command.Registry,
        allocator: std.mem.Allocator,
    ) ![]CommandMatch {
        var matches = std.ArrayList(CommandMatch).init(allocator);
        errdefer matches.deinit();

        const query = self.getQuery();

        // If no query, return all commands
        if (query.len == 0) {
            var iter = registry.commands.iterator();
            while (iter.next()) |entry| {
                try matches.append(.{
                    .name = entry.key_ptr.*,
                    .description = entry.value_ptr.description,
                    .score = 0,
                });
            }
        } else {
            // Filter by fuzzy match
            var iter = registry.commands.iterator();
            while (iter.next()) |entry| {
                const name = entry.key_ptr.*;
                const desc = entry.value_ptr.description;

                if (fuzzyMatch(query, name) or fuzzyMatch(query, desc)) {
                    const score = fuzzyScore(query, name);
                    try matches.append(.{
                        .name = name,
                        .description = desc,
                        .score = score,
                    });
                }
            }

            // Sort by score (descending)
            std.mem.sort(CommandMatch, matches.items, {}, struct {
                fn lessThan(_: void, a: CommandMatch, b: CommandMatch) bool {
                    return a.score > b.score;
                }
            }.lessThan);
        }

        return matches.toOwnedSlice();
    }
};

/// A command match with score
pub const CommandMatch = struct {
    name: []const u8,
    description: []const u8,
    score: usize,
};

/// Simple fuzzy matching - check if all query chars appear in order
fn fuzzyMatch(query: []const u8, text: []const u8) bool {
    if (query.len == 0) return true;

    var query_idx: usize = 0;
    for (text) |c| {
        if (query_idx >= query.len) break;

        // Case-insensitive match
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

    for (text, 0..) |c, i| {
        if (query_idx >= query.len) break;

        const query_c = std.ascii.toLower(query[query_idx]);
        const text_c = std.ascii.toLower(c);

        if (query_c == text_c) {
            query_idx += 1;
            consecutive += 1;

            // Bonus for consecutive matches
            score += 10 + consecutive * 5;

            // Bonus for matching at start
            if (i == 0) score += 20;
        } else {
            consecutive = 0;
        }
    }

    return score;
}

// === Tests ===

test "palette: fuzzy match" {
    try std.testing.expect(fuzzyMatch("ml", "move_left"));
    try std.testing.expect(fuzzyMatch("ins", "insert_mode"));
    try std.testing.expect(!fuzzyMatch("xyz", "move_left"));
}

test "palette: query handling" {
    const allocator = std.testing.allocator;
    var palette = Palette.init(allocator);
    defer palette.deinit();

    try palette.addChar('t');
    try palette.addChar('e');
    try palette.addChar('s');
    try palette.addChar('t');

    try std.testing.expectEqualStrings("test", palette.getQuery());

    palette.backspace();
    try std.testing.expectEqualStrings("tes", palette.getQuery());
}
