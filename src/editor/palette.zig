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
    history: std.ArrayList([]const u8),
    frequency: std.StringHashMap(usize),
    max_history: usize = 50,

    pub fn init(allocator: std.mem.Allocator) Palette {
        return .{
            .allocator = allocator,
            .history = std.ArrayList([]const u8).empty,
            .frequency = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Palette) void {
        // Free history entries
        for (self.history.items) |entry| {
            self.allocator.free(entry);
        }
        self.history.deinit(self.allocator);
        self.frequency.deinit();
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

    /// Record command execution for history and frequency tracking
    pub fn recordExecution(self: *Palette, command_name: []const u8) !void {
        // Update frequency
        const current = self.frequency.get(command_name) orelse 0;
        try self.frequency.put(command_name, current + 1);

        // Add to history (most recent first)
        const name_copy = try self.allocator.dupe(u8, command_name);
        errdefer self.allocator.free(name_copy);

        try self.history.insert(self.allocator, 0, name_copy);

        // Trim history if too long
        while (self.history.items.len > self.max_history) {
            const removed = self.history.items[self.history.items.len - 1];
            self.allocator.free(removed);
            _ = self.history.pop();
        }
    }

    /// Get command frequency (0 if never used)
    pub fn getFrequency(self: *const Palette, command_name: []const u8) usize {
        return self.frequency.get(command_name) orelse 0;
    }

    /// Get recent history (most recent first)
    pub fn getHistory(self: *const Palette) []const []const u8 {
        return self.history.items;
    }

    /// Filter commands based on query
    pub fn filterCommands(
        self: *const Palette,
        registry: *const Command.Registry,
        allocator: std.mem.Allocator,
    ) ![]CommandMatch {
        var matches = std.ArrayList(CommandMatch).empty;
        errdefer matches.deinit(allocator);

        const query = self.getQuery();

        // If no query, return all commands
        if (query.len == 0) {
            var iter = registry.commands.iterator();
            while (iter.next()) |entry| {
                try matches.append(allocator, .{
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
                    var score = fuzzyScore(query, name);

                    // Boost score based on usage frequency
                    const frequency = self.getFrequency(name);
                    score += frequency * 100; // Heavily weight frequently used commands

                    try matches.append(allocator, .{
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

        return matches.toOwnedSlice(allocator);
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

test "palette: command history" {
    const allocator = std.testing.allocator;
    var palette = Palette.init(allocator);
    defer palette.deinit();

    try palette.recordExecution("move_left");
    try palette.recordExecution("save");
    try palette.recordExecution("move_left");

    const history = palette.getHistory();
    try std.testing.expectEqual(@as(usize, 3), history.len);
    try std.testing.expectEqualStrings("move_left", history[0]); // Most recent

    // Check frequency
    try std.testing.expectEqual(@as(usize, 2), palette.getFrequency("move_left"));
    try std.testing.expectEqual(@as(usize, 1), palette.getFrequency("save"));
    try std.testing.expectEqual(@as(usize, 0), palette.getFrequency("unknown"));
}
