//! Enhanced text object implementations
//! Paragraph, indent level, line, and buffer text objects

const std = @import("std");
const Cursor = @import("cursor.zig");
const Buffer = @import("../buffer/manager.zig");

/// Text object result - range of positions
pub const Range = struct {
    start: Cursor.Position,
    end: Cursor.Position,
};

/// Get paragraph text object (around)
/// Paragraph is delimited by blank lines
pub fn selectParagraphAround(
    buffer: *const Buffer.Buffer,
    pos: Cursor.Position,
    allocator: std.mem.Allocator,
) !?Range {
    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    if (text.len == 0) return null;

    // Convert position to byte offset
    const offset = try positionToOffset(text, pos);

    // Find start of paragraph (search backward for blank line)
    var start_offset = offset;
    var i = offset;

    while (i > 0) {
        // Move to start of current line
        while (i > 0 and text[i - 1] != '\n') {
            i -= 1;
        }

        // Check if line is blank
        const line_start = i;
        var line_end = i;
        while (line_end < text.len and text[line_end] != '\n') {
            line_end += 1;
        }

        const is_blank = isLineBlank(text[line_start..line_end]);

        if (is_blank) {
            // Found blank line, paragraph starts after it
            start_offset = line_end + 1; // After newline
            break;
        }

        start_offset = line_start;

        // Move to previous line
        if (i > 0) {
            i -= 1; // Skip newline
        } else {
            break;
        }
    }

    // Find end of paragraph (search forward for blank line)
    var end_offset = offset;
    i = offset;

    while (i < text.len) {
        // Move to start of current line
        while (i > 0 and text[i - 1] != '\n') {
            i -= 1;
        }

        const line_start = i;
        var line_end = i;
        while (line_end < text.len and text[line_end] != '\n') {
            line_end += 1;
        }

        const is_blank = isLineBlank(text[line_start..line_end]);

        if (is_blank) {
            // Found blank line, paragraph ends before it
            end_offset = line_start - 1; // Before newline of blank line
            if (end_offset == 0) end_offset = 0;
            break;
        }

        end_offset = line_end;

        // Move to next line
        if (line_end < text.len) {
            i = line_end + 1;
        } else {
            break;
        }
    }

    const start_pos = try offsetToPosition(text, start_offset);
    const end_pos = try offsetToPosition(text, end_offset);

    return Range{ .start = start_pos, .end = end_pos };
}

/// Get paragraph text object (inside)
/// Same as around but excludes surrounding blank lines
pub fn selectParagraphInside(
    buffer: *const Buffer.Buffer,
    pos: Cursor.Position,
    allocator: std.mem.Allocator,
) !?Range {
    // For paragraphs, inside is the same as around
    return selectParagraphAround(buffer, pos, allocator);
}

/// Get indent level text object (around)
/// Selects lines at same or greater indentation
pub fn selectIndentAround(
    buffer: *const Buffer.Buffer,
    pos: Cursor.Position,
    allocator: std.mem.Allocator,
) !?Range {
    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    if (text.len == 0) return null;

    // Get indentation of current line
    const current_line_start = try getLineStart(text, pos);
    const current_indent = getLineIndentation(text, current_line_start);

    // Find start of indent block (search backward)
    var start_offset = current_line_start;
    var i = current_line_start;

    while (i > 0) {
        // Move to previous line
        i -= 1; // Skip newline
        while (i > 0 and text[i - 1] != '\n') {
            i -= 1;
        }

        const line_start = i;
        const indent = getLineIndentation(text, line_start);

        // Stop if indentation is less than current level (unless blank)
        if (indent < current_indent) {
            const line_end = getLineEnd(text, line_start);
            if (!isLineBlank(text[line_start..line_end])) {
                break;
            }
        }

        start_offset = line_start;

        if (i == 0) break;
    }

    // Find end of indent block (search forward)
    var end_offset = getLineEnd(text, current_line_start);
    i = current_line_start;

    while (i < text.len) {
        const line_start = i;
        const line_end = getLineEnd(text, line_start);
        const indent = getLineIndentation(text, line_start);

        // Stop if indentation is less than current level (unless blank)
        if (indent < current_indent) {
            if (!isLineBlank(text[line_start..line_end])) {
                break;
            }
        }

        end_offset = line_end;

        // Move to next line
        if (line_end < text.len) {
            i = line_end + 1;
        } else {
            break;
        }
    }

    const start_pos = try offsetToPosition(text, start_offset);
    const end_pos = try offsetToPosition(text, end_offset);

    return Range{ .start = start_pos, .end = end_pos };
}

/// Get indent level text object (inside)
/// Same as around
pub fn selectIndentInside(
    buffer: *const Buffer.Buffer,
    pos: Cursor.Position,
    allocator: std.mem.Allocator,
) !?Range {
    return selectIndentAround(buffer, pos, allocator);
}

/// Get line text object (around)
/// Selects entire line including newline
pub fn selectLineAround(
    buffer: *const Buffer.Buffer,
    pos: Cursor.Position,
    allocator: std.mem.Allocator,
) !?Range {
    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    if (text.len == 0) return null;

    const line_start = try getLineStart(text, pos);
    var line_end = getLineEnd(text, line_start);

    // Include newline if present
    if (line_end < text.len and text[line_end] == '\n') {
        line_end += 1;
    }

    const start_pos = try offsetToPosition(text, line_start);
    const end_pos = try offsetToPosition(text, line_end);

    return Range{ .start = start_pos, .end = end_pos };
}

/// Get line text object (inside)
/// Selects line content excluding leading/trailing whitespace and newline
pub fn selectLineInside(
    buffer: *const Buffer.Buffer,
    pos: Cursor.Position,
    allocator: std.mem.Allocator,
) !?Range {
    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    if (text.len == 0) return null;

    var line_start = try getLineStart(text, pos);
    var line_end = getLineEnd(text, line_start);

    // Skip leading whitespace
    while (line_start < line_end and (text[line_start] == ' ' or text[line_start] == '\t')) {
        line_start += 1;
    }

    // Skip trailing whitespace
    while (line_end > line_start and (text[line_end - 1] == ' ' or text[line_end - 1] == '\t')) {
        line_end -= 1;
    }

    const start_pos = try offsetToPosition(text, line_start);
    const end_pos = try offsetToPosition(text, line_end);

    return Range{ .start = start_pos, .end = end_pos };
}

/// Get buffer text object (around)
/// Selects entire buffer
pub fn selectBufferAround(
    buffer: *const Buffer.Buffer,
    allocator: std.mem.Allocator,
) !?Range {
    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);

    if (text.len == 0) return null;

    return Range{
        .start = .{ .line = 0, .col = 0 },
        .end = try offsetToPosition(text, text.len),
    };
}

/// Get buffer text object (inside)
/// Same as around
pub fn selectBufferInside(
    buffer: *const Buffer.Buffer,
    allocator: std.mem.Allocator,
) !?Range {
    return selectBufferAround(buffer, allocator);
}

// === Helper Functions ===

fn isLineBlank(line: []const u8) bool {
    for (line) |ch| {
        if (ch != ' ' and ch != '\t' and ch != '\r') {
            return false;
        }
    }
    return true;
}

fn getLineIndentation(text: []const u8, line_start: usize) usize {
    var indent: usize = 0;
    var i = line_start;

    while (i < text.len) : (i += 1) {
        if (text[i] == ' ') {
            indent += 1;
        } else if (text[i] == '\t') {
            indent += 4; // Assuming tab = 4 spaces
        } else {
            break;
        }
    }

    return indent;
}

fn getLineStart(text: []const u8, pos: Cursor.Position) !usize {
    var offset: usize = 0;
    var line: usize = 0;
    var col: usize = 0;

    while (offset < text.len) {
        if (line == pos.line) {
            // Move back to start of line
            while (offset > 0 and text[offset - 1] != '\n') {
                offset -= 1;
            }
            return offset;
        }

        if (text[offset] == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
        offset += 1;
    }

    return offset;
}

fn getLineEnd(text: []const u8, line_start: usize) usize {
    var i = line_start;
    while (i < text.len and text[i] != '\n') {
        i += 1;
    }
    return i;
}

fn positionToOffset(text: []const u8, pos: Cursor.Position) !usize {
    var offset: usize = 0;
    var line: usize = 0;
    var col: usize = 0;

    while (offset < text.len) {
        if (line == pos.line and col == pos.col) {
            return offset;
        }

        if (text[offset] == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
        offset += 1;
    }

    return offset;
}

fn offsetToPosition(text: []const u8, target_offset: usize) !Cursor.Position {
    var offset: usize = 0;
    var line: usize = 0;
    var col: usize = 0;

    while (offset < target_offset and offset < text.len) {
        if (text[offset] == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
        offset += 1;
    }

    return .{ .line = line, .col = col };
}

// === Tests ===

test "textobject: select paragraph" {
    const allocator = std.testing.allocator;
    const text =
        \\First paragraph
        \\continues here.
        \\
        \\Second paragraph
        \\is here.
    ;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, text);
    defer buffer.deinit();

    // Select from first paragraph
    const range1 = try selectParagraphAround(&buffer, .{ .line = 0, .col = 0 }, allocator);
    try std.testing.expect(range1 != null);
    try std.testing.expectEqual(@as(usize, 0), range1.?.start.line);
    try std.testing.expectEqual(@as(usize, 1), range1.?.end.line);

    // Select from second paragraph
    const range2 = try selectParagraphAround(&buffer, .{ .line = 3, .col = 0 }, allocator);
    try std.testing.expect(range2 != null);
    try std.testing.expectEqual(@as(usize, 3), range2.?.start.line);
}

test "textobject: select line around/inside" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, "  hello world  ");
    defer buffer.deinit();

    // Around includes all
    const around = try selectLineAround(&buffer, .{ .line = 0, .col = 5 }, allocator);
    try std.testing.expect(around != null);
    try std.testing.expectEqual(@as(usize, 0), around.?.start.col);

    // Inside excludes whitespace
    const inside = try selectLineInside(&buffer, .{ .line = 0, .col = 5 }, allocator);
    try std.testing.expect(inside != null);
    try std.testing.expectEqual(@as(usize, 2), inside.?.start.col); // After "  "
}

test "textobject: select buffer" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, "line1\nline2\nline3");
    defer buffer.deinit();

    const range = try selectBufferAround(&buffer, allocator);
    try std.testing.expect(range != null);
    try std.testing.expectEqual(@as(usize, 0), range.?.start.line);
    try std.testing.expectEqual(@as(usize, 0), range.?.start.col);
}

test "textobject: select indent level" {
    const allocator = std.testing.allocator;
    const text =
        \\func main() {
        \\    if (true) {
        \\        code here
        \\        more code
        \\    }
        \\    other
        \\}
    ;
    const buffer = try Buffer.Buffer.initFromString(allocator, 0, text);
    defer buffer.deinit();

    // Select from indented block (line 2)
    const range = try selectIndentAround(&buffer, .{ .line = 2, .col = 0 }, allocator);
    try std.testing.expect(range != null);
    // Should select lines 2-3 (the inner indented block)
    try std.testing.expectEqual(@as(usize, 2), range.?.start.line);
}
