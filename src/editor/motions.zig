//! Motion implementations for cursor movement
//! Handles hjkl, word movements, line start/end, file start/end

const std = @import("std");
const Cursor = @import("cursor.zig");
const Buffer = @import("../buffer/manager.zig");
const Rope = @import("../buffer/rope.zig").Rope;

/// Move cursor left by one character
pub fn moveLeft(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const pos = selection.head;

    // Can't move left from column 0
    if (pos.col == 0) {
        // Try to move to end of previous line
        if (pos.line > 0) {
            const prev_line = pos.line - 1;
            const line_len = getLineLength(buffer, prev_line);
            return selection.moveTo(.{ .line = prev_line, .col = line_len });
        }
        return selection; // At start of file
    }

    return selection.moveTo(.{ .line = pos.line, .col = pos.col - 1 });
}

/// Move cursor right by one character
pub fn moveRight(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const pos = selection.head;
    const line_len = getLineLength(buffer, pos.line);

    // Can move to end of line + 1 (for insert at end)
    if (pos.col >= line_len) {
        // Try to move to start of next line
        const line_count = buffer.rope.lineCount();
        if (pos.line + 1 < line_count) {
            return selection.moveTo(.{ .line = pos.line + 1, .col = 0 });
        }
        return selection; // At end of file
    }

    return selection.moveTo(.{ .line = pos.line, .col = pos.col + 1 });
}

/// Move cursor down by one line
pub fn moveDown(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const pos = selection.head;
    const line_count = buffer.rope.lineCount();

    if (pos.line + 1 >= line_count) {
        return selection; // Already at last line
    }

    const new_line = pos.line + 1;
    const new_line_len = getLineLength(buffer, new_line);
    const new_col = @min(pos.col, new_line_len);

    return selection.moveTo(.{ .line = new_line, .col = new_col });
}

/// Move cursor up by one line
pub fn moveUp(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const pos = selection.head;

    if (pos.line == 0) {
        return selection; // Already at first line
    }

    const new_line = pos.line - 1;
    const new_line_len = getLineLength(buffer, new_line);
    const new_col = @min(pos.col, new_line_len);

    return selection.moveTo(.{ .line = new_line, .col = new_col });
}

/// Move to start of line (column 0)
pub fn moveLineStart(selection: Cursor.Selection, _: *const Buffer.Buffer) Cursor.Selection {
    return selection.moveTo(.{ .line = selection.head.line, .col = 0 });
}

/// Move to end of line
pub fn moveLineEnd(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const line_len = getLineLength(buffer, selection.head.line);
    return selection.moveTo(.{ .line = selection.head.line, .col = line_len });
}

/// Move to start of file (0, 0)
pub fn moveFileStart(selection: Cursor.Selection, _: *const Buffer.Buffer) Cursor.Selection {
    return selection.moveTo(.{ .line = 0, .col = 0 });
}

/// Move to end of file
pub fn moveFileEnd(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const line_count = buffer.rope.lineCount();
    const last_line = if (line_count > 0) line_count - 1 else 0;
    const last_col = getLineLength(buffer, last_line);

    return selection.moveTo(.{ .line = last_line, .col = last_col });
}

/// Move forward to start of next word
pub fn moveWordForward(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const pos = selection.head;
    const allocator = std.heap.page_allocator;

    // Get current line
    const line_text = getLineText(allocator, buffer, pos.line) catch return selection;
    defer allocator.free(line_text);

    if (pos.col >= line_text.len) {
        // At end of line, move to next line
        return moveRight(selection, buffer);
    }

    var col = pos.col;
    const in_word = isWordChar(line_text[col]);

    // Skip current word/whitespace
    while (col < line_text.len and isWordChar(line_text[col]) == in_word) {
        col += 1;
    }

    // Skip whitespace to next word
    while (col < line_text.len and !isWordChar(line_text[col])) {
        col += 1;
    }

    if (col >= line_text.len) {
        // Reached end of line, move to next line start
        const line_count = buffer.rope.lineCount();
        if (pos.line + 1 < line_count) {
            return selection.moveTo(.{ .line = pos.line + 1, .col = 0 });
        }
    }

    return selection.moveTo(.{ .line = pos.line, .col = col });
}

/// Move backward to start of current/previous word
pub fn moveWordBackward(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const pos = selection.head;
    const allocator = std.heap.page_allocator;

    if (pos.col == 0) {
        // At start of line, move to end of previous line
        if (pos.line > 0) {
            const prev_line = pos.line - 1;
            const prev_len = getLineLength(buffer, prev_line);
            return selection.moveTo(.{ .line = prev_line, .col = prev_len });
        }
        return selection; // At start of file
    }

    // Get current line
    const line_text = getLineText(allocator, buffer, pos.line) catch return selection;
    defer allocator.free(line_text);

    var col = pos.col;
    if (col > line_text.len) col = line_text.len;

    // Move back one to start search
    if (col > 0) col -= 1;

    // Skip whitespace
    while (col > 0 and !isWordChar(line_text[col])) {
        col -= 1;
    }

    // Skip word characters to find start
    while (col > 0 and isWordChar(line_text[col])) {
        col -= 1;
    }

    // Adjust if we stopped on a non-word char
    if (!isWordChar(line_text[col]) and col < line_text.len - 1) {
        col += 1;
    }

    return selection.moveTo(.{ .line = pos.line, .col = col });
}

/// Move forward to end of current/next word
pub fn moveWordEnd(selection: Cursor.Selection, buffer: *const Buffer.Buffer) Cursor.Selection {
    const pos = selection.head;
    const allocator = std.heap.page_allocator;

    // Get current line
    const line_text = getLineText(allocator, buffer, pos.line) catch return selection;
    defer allocator.free(line_text);

    if (pos.col >= line_text.len) {
        // At end of line, move to next line
        return moveRight(selection, buffer);
    }

    var col = pos.col;

    // If on word char, skip to end of word
    if (isWordChar(line_text[col])) {
        while (col < line_text.len and isWordChar(line_text[col])) {
            col += 1;
        }
        col -= 1; // Move back to last char of word
    } else {
        // Skip whitespace to next word
        while (col < line_text.len and !isWordChar(line_text[col])) {
            col += 1;
        }
        // Now skip to end of that word
        while (col < line_text.len and isWordChar(line_text[col])) {
            col += 1;
        }
        if (col > 0) col -= 1; // Move back to last char of word
    }

    return selection.moveTo(.{ .line = pos.line, .col = col });
}

// === Helper functions ===

/// Get length of a line (in characters, not bytes)
fn getLineLength(buffer: *const Buffer.Buffer, line: usize) usize {
    const allocator = std.heap.page_allocator;
    const line_text = getLineText(allocator, buffer, line) catch return 0;
    defer allocator.free(line_text);

    return std.unicode.utf8CountCodepoints(line_text) catch line_text.len;
}

/// Get text of a specific line
fn getLineText(allocator: std.mem.Allocator, buffer: *const Buffer.Buffer, line: usize) ![]u8 {
    const line_count = buffer.rope.lineCount();
    if (line >= line_count) return allocator.alloc(u8, 0);

    // Find byte offset of line start
    var current_line: usize = 0;
    var byte_offset: usize = 0;
    const total_bytes = buffer.rope.len();

    while (current_line < line and byte_offset < total_bytes) {
        const text = try buffer.rope.slice(allocator, byte_offset, total_bytes);
        defer allocator.free(text);

        // Find next newline
        for (text, 0..) |ch, i| {
            if (ch == '\n') {
                byte_offset += i + 1;
                current_line += 1;
                break;
            }
        }

        if (current_line < line and byte_offset >= total_bytes) break;
    }

    // Now get the line text
    const line_start = byte_offset;
    var line_end = byte_offset;

    if (line_start < total_bytes) {
        const remaining = try buffer.rope.slice(allocator, line_start, total_bytes);
        defer allocator.free(remaining);

        for (remaining, 0..) |ch, i| {
            if (ch == '\n') {
                line_end = line_start + i;
                break;
            }
        }

        if (line_end == line_start) {
            line_end = total_bytes;
        }
    }

    return buffer.rope.slice(allocator, line_start, line_end);
}

/// Check if character is a word character (alphanumeric or underscore)
fn isWordChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_';
}

/// Check if character is an opening bracket
fn isOpenBracket(ch: u8) bool {
    return ch == '(' or ch == '[' or ch == '{';
}

/// Check if character is a closing bracket
fn isCloseBracket(ch: u8) bool {
    return ch == ')' or ch == ']' or ch == '}';
}

/// Get matching bracket character
fn getMatchingBracket(ch: u8) ?u8 {
    return switch (ch) {
        '(' => ')',
        ')' => '(',
        '[' => ']',
        ']' => '[',
        '{' => '}',
        '}' => '{',
        else => null,
    };
}

/// Jump to matching bracket/brace/parenthesis
pub fn jumpToMatchingBracket(selection: Cursor.Selection, buffer: *const Buffer.Buffer) !Cursor.Selection {
    const allocator = std.heap.page_allocator;

    // Get buffer text
    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    if (text.len == 0) return selection;

    // Convert position to byte offset
    var offset: usize = 0;
    var line: usize = 0;
    var col: usize = 0;

    while (offset < text.len) {
        if (line == selection.head.line and col == selection.head.col) {
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

    if (offset >= text.len) return selection;

    const current_char = text[offset];
    const matching_char = getMatchingBracket(current_char) orelse return selection;

    // Determine search direction
    const is_forward = isOpenBracket(current_char);
    var search_offset = offset;
    var depth: i32 = 1;

    if (is_forward) {
        // Search forward
        search_offset += 1;
        while (search_offset < text.len) {
            const ch = text[search_offset];
            if (ch == current_char) {
                depth += 1;
            } else if (ch == matching_char) {
                depth -= 1;
                if (depth == 0) {
                    // Found matching bracket
                    var match_line: usize = 0;
                    var match_col: usize = 0;
                    var i: usize = 0;
                    while (i <= search_offset) : (i += 1) {
                        if (text[i] == '\n') {
                            match_line += 1;
                            match_col = 0;
                        } else {
                            match_col += 1;
                        }
                    }
                    // Adjust for the last character
                    if (match_col > 0) match_col -= 1;

                    return selection.moveTo(.{ .line = match_line, .col = match_col });
                }
            }
            search_offset += 1;
        }
    } else {
        // Search backward
        if (search_offset == 0) return selection;
        search_offset -= 1;

        while (true) {
            const ch = text[search_offset];
            if (ch == current_char) {
                depth += 1;
            } else if (ch == matching_char) {
                depth -= 1;
                if (depth == 0) {
                    // Found matching bracket
                    var match_line: usize = 0;
                    var match_col: usize = 0;
                    var i: usize = 0;
                    while (i <= search_offset) : (i += 1) {
                        if (text[i] == '\n') {
                            match_line += 1;
                            match_col = 0;
                        } else {
                            match_col += 1;
                        }
                    }
                    // Adjust for the last character
                    if (match_col > 0) match_col -= 1;

                    return selection.moveTo(.{ .line = match_line, .col = match_col });
                }
            }

            if (search_offset == 0) break;
            search_offset -= 1;
        }
    }

    // No matching bracket found
    return selection;
}

// === Tests ===

test "motion: move left" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello\nworld");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 0, .col = 3 });
    const moved = moveLeft(sel, &buffer);

    try std.testing.expectEqual(@as(usize, 0), moved.head.line);
    try std.testing.expectEqual(@as(usize, 2), moved.head.col);
}

test "motion: move right" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello\nworld");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 0, .col = 2 });
    const moved = moveRight(sel, &buffer);

    try std.testing.expectEqual(@as(usize, 0), moved.head.line);
    try std.testing.expectEqual(@as(usize, 3), moved.head.col);
}

test "motion: move down" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello\nworld");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 0, .col = 2 });
    const moved = moveDown(sel, &buffer);

    try std.testing.expectEqual(@as(usize, 1), moved.head.line);
    try std.testing.expectEqual(@as(usize, 2), moved.head.col);
}

test "motion: move up" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello\nworld");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 1, .col = 2 });
    const moved = moveUp(sel, &buffer);

    try std.testing.expectEqual(@as(usize, 0), moved.head.line);
    try std.testing.expectEqual(@as(usize, 2), moved.head.col);
}

test "motion: line start/end" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 0, .col = 2 });

    const start = moveLineStart(sel, &buffer);
    try std.testing.expectEqual(@as(usize, 0), start.head.col);

    const end = moveLineEnd(sel, &buffer);
    try std.testing.expectEqual(@as(usize, 5), end.head.col);
}

test "motion: file start/end" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello\nworld");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 1, .col = 2 });

    const start = moveFileStart(sel, &buffer);
    try std.testing.expectEqual(@as(usize, 0), start.head.line);
    try std.testing.expectEqual(@as(usize, 0), start.head.col);

    const end = moveFileEnd(sel, &buffer);
    try std.testing.expectEqual(@as(usize, 1), end.head.line);
}
