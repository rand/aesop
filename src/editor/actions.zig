//! Text editing actions (insert, delete, change, yank, paste)
//! Operates on buffer content through the rope data structure

const std = @import("std");
const Cursor = @import("cursor.zig");
const Buffer = @import("../buffer/manager.zig");
const Rope = @import("../buffer/rope.zig").Rope;

/// Clipboard for yank/paste operations
pub const Clipboard = struct {
    content: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Clipboard {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Clipboard) void {
        if (self.content) |content| {
            self.allocator.free(content);
        }
    }

    pub fn setContent(self: *Clipboard, text: []const u8) !void {
        // Free old content
        if (self.content) |old| {
            self.allocator.free(old);
        }

        // Copy new content
        self.content = try self.allocator.dupe(u8, text);
    }

    pub fn getContent(self: *const Clipboard) ?[]const u8 {
        return self.content;
    }
};

/// Insert text at cursor position
pub fn insertText(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
    text: []const u8,
) !Cursor.Selection {
    const pos = selection.head;
    const byte_offset = try positionToByteOffset(buffer, pos);

    // Insert text into rope
    try buffer.rope.insert(byte_offset, text);

    // Update cursor position (move to end of inserted text)
    const new_col = pos.col + text.len; // Simplified - should count characters
    const new_pos = Cursor.Position{ .line = pos.line, .col = new_col };

    return selection.moveTo(new_pos);
}

/// Insert newline at cursor position
pub fn insertNewline(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    const pos = selection.head;
    const byte_offset = try positionToByteOffset(buffer, pos);

    // Insert newline
    try buffer.rope.insert(byte_offset, "\n");

    // Move cursor to start of next line
    const new_pos = Cursor.Position{ .line = pos.line + 1, .col = 0 };
    return selection.moveTo(new_pos);
}

/// Delete character at cursor position (like 'x' in vim)
pub fn deleteChar(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    const pos = selection.head;
    const byte_offset = try positionToByteOffset(buffer, pos);

    // Don't delete if at end of file
    if (byte_offset >= buffer.rope.len()) {
        return selection;
    }

    // Delete one byte (simplified - should handle UTF-8 properly)
    try buffer.rope.delete(byte_offset, byte_offset + 1);

    return selection;
}

/// Delete character before cursor (like backspace)
pub fn deleteCharBefore(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    const pos = selection.head;

    // Can't delete before column 0
    if (pos.col == 0) {
        // Could handle line joining here
        return selection;
    }

    const byte_offset = try positionToByteOffset(buffer, pos);

    // Delete one byte before cursor
    if (byte_offset > 0) {
        try buffer.rope.delete(byte_offset - 1, byte_offset);

        // Move cursor back
        const new_pos = Cursor.Position{ .line = pos.line, .col = pos.col - 1 };
        return selection.moveTo(new_pos);
    }

    return selection;
}

/// Delete text in selection range
pub fn deleteSelection(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
    clipboard: ?*Clipboard,
) !Cursor.Selection {
    if (selection.isCollapsed()) {
        return selection; // Nothing to delete
    }

    const range = selection.range();
    const start_offset = try positionToByteOffset(buffer, range.start);
    const end_offset = try positionToByteOffset(buffer, range.end);

    // Yank to clipboard if provided
    if (clipboard) |clip| {
        const allocator = clip.allocator;
        const text = try buffer.rope.slice(allocator, start_offset, end_offset);
        defer allocator.free(text);
        try clip.setContent(text);
    }

    // Delete the range
    try buffer.rope.delete(start_offset, end_offset);

    // Collapse selection to start
    return selection.collapseToAnchor();
}

/// Yank (copy) selection to clipboard
pub fn yankSelection(
    buffer: *const Buffer.Buffer,
    selection: Cursor.Selection,
    clipboard: *Clipboard,
) !void {
    if (selection.isCollapsed()) {
        return; // Nothing to yank
    }

    const range = selection.range();
    const start_offset = try positionToByteOffset(buffer, range.start);
    const end_offset = try positionToByteOffset(buffer, range.end);

    const allocator = clipboard.allocator;
    const text = try buffer.rope.slice(allocator, start_offset, end_offset);
    defer allocator.free(text);

    try clipboard.setContent(text);
}

/// Paste clipboard content at cursor
pub fn pasteAfter(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
    clipboard: *const Clipboard,
) !Cursor.Selection {
    const content = clipboard.getContent() orelse return selection;

    const pos = selection.head;
    const byte_offset = try positionToByteOffset(buffer, pos);

    // Insert after current position
    const insert_offset = if (byte_offset < buffer.rope.len())
        byte_offset + 1
    else
        byte_offset;

    try buffer.rope.insert(insert_offset, content);

    // Move cursor to end of pasted text
    const new_col = pos.col + 1 + content.len; // Simplified
    const new_pos = Cursor.Position{ .line = pos.line, .col = new_col };

    return selection.moveTo(new_pos);
}

/// Paste clipboard content before cursor
pub fn pasteBefore(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
    clipboard: *const Clipboard,
) !Cursor.Selection {
    const content = clipboard.getContent() orelse return selection;

    const pos = selection.head;
    const byte_offset = try positionToByteOffset(buffer, pos);

    try buffer.rope.insert(byte_offset, content);

    // Move cursor to end of pasted text
    const new_col = pos.col + content.len; // Simplified
    const new_pos = Cursor.Position{ .line = pos.line, .col = new_col };

    return selection.moveTo(new_pos);
}

/// Change (delete and enter insert mode) - helper for command layer
pub fn changeSelection(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
    clipboard: ?*Clipboard,
) !Cursor.Selection {
    // Same as delete - the mode transition happens at command level
    return deleteSelection(buffer, selection, clipboard);
}

// === Helper functions ===

/// Convert Position (line, col) to byte offset in rope
pub fn positionToByteOffset(buffer: *const Buffer.Buffer, pos: Cursor.Position) !usize {
    const allocator = std.heap.page_allocator;

    var current_line: usize = 0;
    var byte_offset: usize = 0;
    const total_bytes = buffer.rope.len();

    // Find byte offset of line start
    while (current_line < pos.line and byte_offset < total_bytes) {
        // Scan for newline
        const remaining = try buffer.rope.slice(allocator, byte_offset, total_bytes);
        defer allocator.free(remaining);

        var found = false;
        for (remaining, 0..) |ch, i| {
            if (ch == '\n') {
                byte_offset += i + 1;
                current_line += 1;
                found = true;
                break;
            }
        }

        if (!found) break; // Reached end without finding newline
    }

    // Now add column offset
    if (pos.col > 0) {
        const line_start = byte_offset;
        const remaining = try buffer.rope.slice(allocator, line_start, total_bytes);
        defer allocator.free(remaining);

        var col: usize = 0;
        for (remaining, 0..) |ch, i| {
            if (ch == '\n') break;
            if (col >= pos.col) break;

            byte_offset += 1;
            col += 1;

            _ = i; // Unused but kept for clarity
        }
    }

    return @min(byte_offset, total_bytes);
}

// === Tests ===

test "actions: insert text" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 0, .col = 5 });
    const new_sel = try insertText(&buffer, sel, " world");

    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("hello world", text);
    try std.testing.expectEqual(@as(usize, 11), new_sel.head.col);
}

test "actions: insert newline" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 0, .col = 5 });
    const new_sel = try insertNewline(&buffer, sel);

    try std.testing.expectEqual(@as(usize, 1), new_sel.head.line);
    try std.testing.expectEqual(@as(usize, 0), new_sel.head.col);
}

test "actions: delete char" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello");
    defer buffer.deinit();

    const sel = Cursor.Selection.cursor(.{ .line = 0, .col = 0 });
    _ = try deleteChar(&buffer, sel);

    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("ello", text);
}

test "actions: clipboard yank and paste" {
    const allocator = std.testing.allocator;
    var clipboard = Clipboard.init(allocator);
    defer clipboard.deinit();

    var buffer = try Buffer.Buffer.initFromString(allocator, 0, "hello world");
    defer buffer.deinit();

    // Yank "hello"
    const sel = Cursor.Selection.init(.{ .line = 0, .col = 0 }, .{ .line = 0, .col = 5 });
    try yankSelection(&buffer, sel, &clipboard);

    try std.testing.expect(clipboard.getContent() != null);
    try std.testing.expectEqualStrings("hello", clipboard.getContent().?);

    // Paste at end
    const paste_sel = Cursor.Selection.cursor(.{ .line = 0, .col = 10 });
    _ = try pasteAfter(&buffer, paste_sel, &clipboard);

    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("hello worldhello", text);
}

// === Line Operations ===

/// Get the start and end byte offsets of a line
fn getLineRange(buffer: *const Buffer.Buffer, line_num: usize) !struct { start: usize, end: usize } {
    const allocator = std.heap.page_allocator;
    const total_bytes = buffer.rope.len();

    var current_line: usize = 0;
    var line_start: usize = 0;
    var byte_offset: usize = 0;

    // Find start of target line
    while (current_line < line_num and byte_offset < total_bytes) {
        const remaining = try buffer.rope.slice(allocator, byte_offset, total_bytes);
        defer allocator.free(remaining);

        if (std.mem.indexOfScalar(u8, remaining, '\n')) |newline_pos| {
            byte_offset += newline_pos + 1;
            current_line += 1;
            if (current_line == line_num) {
                line_start = byte_offset;
            }
        } else {
            break;
        }
    }

    // If we didn't reach the line, it doesn't exist
    if (current_line < line_num) {
        return error.LineNotFound;
    }

    if (current_line == line_num) {
        line_start = byte_offset;
    }

    // Find end of line (next newline or EOF)
    var line_end = line_start;
    if (line_start < total_bytes) {
        const remaining = try buffer.rope.slice(allocator, line_start, total_bytes);
        defer allocator.free(remaining);

        if (std.mem.indexOfScalar(u8, remaining, '\n')) |newline_pos| {
            line_end = line_start + newline_pos + 1; // Include newline
        } else {
            line_end = total_bytes; // Last line without newline
        }
    }

    return .{ .start = line_start, .end = line_end };
}

/// Move line up (swap with previous line)
pub fn moveLineUp(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    const line_num = selection.head.line;

    // Can't move first line up
    if (line_num == 0) {
        return selection;
    }

    const allocator = std.heap.page_allocator;

    // Get current line and previous line ranges
    const curr_range = try getLineRange(buffer, line_num);
    const prev_range = try getLineRange(buffer, line_num - 1);

    // Get line contents
    const curr_text = try buffer.rope.slice(allocator, curr_range.start, curr_range.end);
    defer allocator.free(curr_text);
    const prev_text = try buffer.rope.slice(allocator, prev_range.start, prev_range.end);
    defer allocator.free(prev_text);

    // Delete both lines
    try buffer.rope.delete(prev_range.start, curr_range.end);

    // Insert in swapped order
    try buffer.rope.insert(prev_range.start, curr_text);
    const curr_len = curr_text.len;
    try buffer.rope.insert(prev_range.start + curr_len, prev_text);

    // Move cursor up one line
    const new_pos = Cursor.Position{ .line = line_num - 1, .col = selection.head.col };
    return selection.moveTo(new_pos);
}

/// Move line down (swap with next line)
pub fn moveLineDown(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    const line_num = selection.head.line;
    const allocator = std.heap.page_allocator;

    // Check if next line exists
    const curr_range = try getLineRange(buffer, line_num);
    const next_range = getLineRange(buffer, line_num + 1) catch {
        // No next line
        return selection;
    };

    // Get line contents
    const curr_text = try buffer.rope.slice(allocator, curr_range.start, curr_range.end);
    defer allocator.free(curr_text);
    const next_text = try buffer.rope.slice(allocator, next_range.start, next_range.end);
    defer allocator.free(next_text);

    // Delete both lines
    try buffer.rope.delete(curr_range.start, next_range.end);

    // Insert in swapped order
    try buffer.rope.insert(curr_range.start, next_text);
    const next_len = next_text.len;
    try buffer.rope.insert(curr_range.start + next_len, curr_text);

    // Move cursor down one line
    const new_pos = Cursor.Position{ .line = line_num + 1, .col = selection.head.col };
    return selection.moveTo(new_pos);
}

// === Word Operations ===

/// Check if a character is a word character
fn isWordChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_';
}

/// Find word boundaries at the given position
fn getWordBounds(buffer: *const Buffer.Buffer, pos: Cursor.Position) !struct { start: Cursor.Position, end: Cursor.Position } {
    const allocator = std.heap.page_allocator;
    const total_bytes = buffer.rope.len();

    if (total_bytes == 0) {
        return .{ .start = pos, .end = pos };
    }

    // Get the full text (simplified - should use rope operations)
    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    // Find line boundaries
    var line_start: usize = 0;
    var line_num: usize = 0;
    for (text, 0..) |ch, i| {
        if (line_num == pos.line) {
            line_start = i;
            break;
        }
        if (ch == '\n') {
            line_num += 1;
        }
    }

    // Get line text
    const line_end_idx = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
    const line_text = text[line_start..line_end_idx];

    if (pos.col >= line_text.len) {
        return .{ .start = pos, .end = pos };
    }

    // If on whitespace, no word
    if (!isWordChar(line_text[pos.col])) {
        return .{ .start = pos, .end = pos };
    }

    // Find word start
    var word_start_col = pos.col;
    while (word_start_col > 0 and isWordChar(line_text[word_start_col - 1])) {
        word_start_col -= 1;
    }

    // Find word end
    var word_end_col = pos.col;
    while (word_end_col < line_text.len and isWordChar(line_text[word_end_col])) {
        word_end_col += 1;
    }

    return .{
        .start = .{ .line = pos.line, .col = word_start_col },
        .end = .{ .line = pos.line, .col = word_end_col },
    };
}

/// Select the word under cursor
pub fn selectWord(
    buffer: *const Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    const bounds = try getWordBounds(buffer, selection.head);
    return Cursor.Selection.init(bounds.start, bounds.end);
}

/// Delete the word under cursor
pub fn deleteWord(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    const bounds = try getWordBounds(buffer, selection.head);

    // If no word at cursor, do nothing
    if (bounds.start.eql(bounds.end)) {
        return selection;
    }

    // Convert positions to byte offsets
    const start_offset = try positionToByteOffset(buffer, bounds.start);
    const end_offset = try positionToByteOffset(buffer, bounds.end);

    // Delete the word
    try buffer.rope.delete(start_offset, end_offset);

    // Return selection at word start
    return Cursor.Selection.cursor(bounds.start);
}

/// Change word (delete and return selection for insert mode)
pub fn changeWord(
    buffer: *Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    return deleteWord(buffer, selection);
}

/// Select inside word (same as selectWord for now)
pub fn selectInnerWord(
    buffer: *const Buffer.Buffer,
    selection: Cursor.Selection,
) !Cursor.Selection {
    return selectWord(buffer, selection);
}
