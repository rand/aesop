//! Auto-pairing for brackets, quotes, and other delimiters
//! Automatically inserts closing characters and manages cursor positioning

const std = @import("std");

/// Auto-pair configuration
pub const AutoPairConfig = struct {
    enabled: bool = true,
    pairs: []const Pair = &default_pairs,

    pub const Pair = struct {
        open: u21,
        close: u21,
    };
};

/// Default auto-pair characters
const default_pairs = [_]AutoPairConfig.Pair{
    .{ .open = '(', .close = ')' },
    .{ .open = '[', .close = ']' },
    .{ .open = '{', .close = '}' },
    .{ .open = '"', .close = '"' },
    .{ .open = '\'', .close = '\'' },
    .{ .open = '`', .close = '`' },
};

/// Check if character should trigger auto-pairing
pub fn shouldAutoPair(config: AutoPairConfig, char: u21) bool {
    if (!config.enabled) return false;

    for (config.pairs) |pair| {
        if (char == pair.open) return true;
        // For symmetric pairs (quotes), also match on close
        if (char == pair.close and pair.open == pair.close) return true;
    }
    return false;
}

/// Get closing character for opening character
pub fn getClosingChar(config: AutoPairConfig, open_char: u21) ?u21 {
    for (config.pairs) |pair| {
        if (open_char == pair.open) return pair.close;
    }
    return null;
}

/// Check if we should skip over closing character (when cursor is before it)
pub fn shouldSkipClosing(config: AutoPairConfig, char: u21, next_char: ?u21) bool {
    if (!config.enabled) return false;
    if (next_char == null) return false;

    for (config.pairs) |pair| {
        // If typing the close character and it's next, skip over it
        if (char == pair.close and next_char.? == char) {
            return true;
        }
    }
    return false;
}

/// Get the paired text to insert (includes both opening and closing)
pub fn getPairedText(
    config: AutoPairConfig,
    open_char: u21,
    allocator: std.mem.Allocator,
) !?[]const u8 {
    if (!config.enabled) return null;

    const close_char = getClosingChar(config, open_char) orelse return null;

    // Create string with both characters
    var buf: [8]u8 = undefined; // Max 4 bytes per UTF-8 char
    const open_len = try std.unicode.utf8Encode(open_char, buf[0..]);
    const close_len = try std.unicode.utf8Encode(close_char, buf[open_len..]);

    const result = try allocator.alloc(u8, open_len + close_len);
    @memcpy(result[0..open_len], buf[0..open_len]);
    @memcpy(result[open_len..], buf[open_len..open_len + close_len]);

    return result;
}

// === Tests ===

test "autopair: should auto-pair brackets" {
    const config = AutoPairConfig{};

    try std.testing.expect(shouldAutoPair(config, '('));
    try std.testing.expect(shouldAutoPair(config, '['));
    try std.testing.expect(shouldAutoPair(config, '{'));
    try std.testing.expect(!shouldAutoPair(config, 'a'));
}

test "autopair: should auto-pair quotes" {
    const config = AutoPairConfig{};

    try std.testing.expect(shouldAutoPair(config, '"'));
    try std.testing.expect(shouldAutoPair(config, '\''));
    try std.testing.expect(shouldAutoPair(config, '`'));
}

test "autopair: get closing character" {
    const config = AutoPairConfig{};

    try std.testing.expectEqual(@as(u21, ')'), getClosingChar(config, '(').?);
    try std.testing.expectEqual(@as(u21, ']'), getClosingChar(config, '[').?);
    try std.testing.expectEqual(@as(u21, '}'), getClosingChar(config, '{').?);
    try std.testing.expectEqual(@as(u21, '"'), getClosingChar(config, '"').?);
}

test "autopair: should skip closing" {
    const config = AutoPairConfig{};

    try std.testing.expect(shouldSkipClosing(config, ')', ')'));
    try std.testing.expect(shouldSkipClosing(config, ']', ']'));
    try std.testing.expect(!shouldSkipClosing(config, ')', '('));
    try std.testing.expect(!shouldSkipClosing(config, ')', null));
}

test "autopair: get paired text" {
    const allocator = std.testing.allocator;
    const config = AutoPairConfig{};

    const paired = try getPairedText(config, '(', allocator);
    defer if (paired) |p| allocator.free(p);

    try std.testing.expect(paired != null);
    try std.testing.expectEqualStrings("()", paired.?);
}
