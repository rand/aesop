//! Popup/overlay rendering for hover and other contextual information
//! Displays content in a floating box near the cursor

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

/// Popup configuration
pub const PopupConfig = struct {
    /// Maximum width of popup (chars)
    max_width: u16 = 60,
    /// Maximum height of popup (lines)
    max_height: u16 = 15,
    /// Border style
    border: BorderStyle = .single,
    /// Title (optional)
    title: ?[]const u8 = null,

    pub const BorderStyle = enum {
        none,
        single,
        double,
    };
};

/// Popup position relative to cursor
pub const PopupPosition = struct {
    row: u16,
    col: u16,
};

/// Calculate optimal popup position near cursor
/// Tries to place popup below and right of cursor, but adjusts if near screen edges
pub fn calculatePosition(
    screen_width: u16,
    screen_height: u16,
    cursor_row: u16,
    cursor_col: u16,
    popup_width: u16,
    popup_height: u16,
) PopupPosition {
    // Try to place below cursor (1 row down)
    var row = cursor_row + 1;
    var col = cursor_col;

    // If popup would go off bottom, place above cursor
    if (row + popup_height >= screen_height) {
        if (cursor_row >= popup_height) {
            row = cursor_row - popup_height;
        } else {
            // Not enough space above either, center vertically
            row = (screen_height -| popup_height) / 2;
        }
    }

    // If popup would go off right edge, shift left
    if (col + popup_width >= screen_width) {
        if (screen_width >= popup_width) {
            col = screen_width - popup_width;
        } else {
            col = 0;
        }
    }

    return .{ .row = row, .col = col };
}

/// Render a popup with given content
pub fn render(
    rend: *renderer.Renderer,
    position: PopupPosition,
    width: u16,
    height: u16,
    content: []const u8,
    config: PopupConfig,
) !void {
    const size = rend.getSize();

    // Clamp dimensions to screen size
    const actual_width = @min(width, size.width -| position.col);
    const actual_height = @min(height, size.height -| position.row);

    if (actual_width == 0 or actual_height == 0) return;

    // Draw border
    if (config.border != .none) {
        try renderBorder(rend, position, actual_width, actual_height, config);
    }

    // Calculate content area (inside border)
    const content_row = if (config.border != .none) position.row + 1 else position.row;
    const content_col = if (config.border != .none) position.col + 1 else position.col;
    const content_width = if (config.border != .none) actual_width -| 2 else actual_width;
    const content_height = if (config.border != .none) actual_height -| 2 else actual_height;

    // Render content (word-wrapped)
    try renderContent(rend, content_row, content_col, content_width, content_height, content);
}

/// Render popup border
fn renderBorder(
    rend: *renderer.Renderer,
    position: PopupPosition,
    width: u16,
    height: u16,
    config: PopupConfig,
) !void {
    const chars = getBorderChars(config.border);

    // Top border
    var col = position.col;
    rend.output.setCell(position.row, col, .{
        .char = chars.top_left,
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });
    col += 1;

    // Title or horizontal line
    if (config.title) |title| {
        const title_text = if (title.len + 4 > width) title[0..width -| 4] else title;
        rend.writeText(
            position.row,
            col,
            " ",
            .{ .standard = .white },
            .{ .standard = .black },
            .{},
        );
        col += 1;

        rend.writeText(
            position.row,
            col,
            title_text,
            .{ .standard = .bright_white },
            .{ .standard = .black },
            .{ .bold = true },
        );
        col += @intCast(title_text.len);

        rend.writeText(
            position.row,
            col,
            " ",
            .{ .standard = .white },
            .{ .standard = .black },
            .{},
        );
        col += 1;
    }

    while (col < position.col + width - 1) : (col += 1) {
        rend.output.setCell(position.row, col, .{
            .char = chars.horizontal,
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }

    rend.output.setCell(position.row, col, .{
        .char = chars.top_right,
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });

    // Side borders
    var row: u16 = position.row + 1;
    while (row < position.row + height - 1) : (row += 1) {
        rend.output.setCell(row, position.col, .{
            .char = chars.vertical,
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
        rend.output.setCell(row, position.col + width - 1, .{
            .char = chars.vertical,
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });

        // Fill interior with background
        col = position.col + 1;
        while (col < position.col + width - 1) : (col += 1) {
            rend.output.setCell(row, col, .{
                .char = ' ',
                .fg = .{ .standard = .white },
                .bg = .{ .standard = .black },
                .attrs = .{},
            });
        }
    }

    // Bottom border
    col = position.col;
    rend.output.setCell(position.row + height - 1, col, .{
        .char = chars.bottom_left,
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });
    col += 1;

    while (col < position.col + width - 1) : (col += 1) {
        rend.output.setCell(position.row + height - 1, col, .{
            .char = chars.horizontal,
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }

    rend.output.setCell(position.row + height - 1, col, .{
        .char = chars.bottom_right,
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });
}

/// Render content with word wrapping
fn renderContent(
    rend: *renderer.Renderer,
    start_row: u16,
    start_col: u16,
    width: u16,
    height: u16,
    content: []const u8,
) !void {
    var row = start_row;
    var col = start_col;
    var line_start: usize = 0;

    var i: usize = 0;
    while (i < content.len and row < start_row + height) {
        const char = content[i];

        if (char == '\n') {
            // Render current line
            if (line_start < i) {
                const line = content[line_start..i];
                rend.writeText(
                    row,
                    start_col,
                    line[0..@min(line.len, width)],
                    .{ .standard = .bright_white },
                    .{ .standard = .black },
                    .{},
                );
            }

            row += 1;
            col = start_col;
            line_start = i + 1;
            i += 1;
            continue;
        }

        // Check if we need to wrap
        const line_len = i - line_start;
        if (line_len >= width) {
            // Find last space for word wrap
            var wrap_point = i;
            var j = i;
            while (j > line_start and content[j] != ' ') {
                j -= 1;
            }
            if (j > line_start) {
                wrap_point = j;
            }

            // Render line up to wrap point
            const line = content[line_start..wrap_point];
            rend.writeText(
                row,
                start_col,
                line,
                .{ .standard = .bright_white },
                .{ .standard = .black },
                .{},
            );

            row += 1;
            col = start_col;
            line_start = if (content[wrap_point] == ' ') wrap_point + 1 else wrap_point;
            i = line_start;
            continue;
        }

        i += 1;
    }

    // Render final line
    if (line_start < content.len and row < start_row + height) {
        const line = content[line_start..];
        rend.writeText(
            row,
            start_col,
            line[0..@min(line.len, width)],
            .{ .standard = .bright_white },
            .{ .standard = .black },
            .{},
        );
    }
}

/// Get border characters for style
fn getBorderChars(style: PopupConfig.BorderStyle) struct {
    top_left: u21,
    top_right: u21,
    bottom_left: u21,
    bottom_right: u21,
    horizontal: u21,
    vertical: u21,
} {
    return switch (style) {
        .none => .{
            .top_left = ' ',
            .top_right = ' ',
            .bottom_left = ' ',
            .bottom_right = ' ',
            .horizontal = ' ',
            .vertical = ' ',
        },
        .single => .{
            .top_left = '┌',
            .top_right = '┐',
            .bottom_left = '└',
            .bottom_right = '┘',
            .horizontal = '─',
            .vertical = '│',
        },
        .double => .{
            .top_left = '╔',
            .top_right = '╗',
            .bottom_left = '╚',
            .bottom_right = '╝',
            .horizontal = '═',
            .vertical = '║',
        },
    };
}

/// Calculate content dimensions (for positioning)
pub fn calculateDimensions(
    content: []const u8,
    config: PopupConfig,
) struct { width: u16, height: u16 } {
    var max_line_len: usize = 0;
    var line_count: usize = 1;
    var current_line_len: usize = 0;

    for (content) |char| {
        if (char == '\n') {
            max_line_len = @max(max_line_len, current_line_len);
            current_line_len = 0;
            line_count += 1;
        } else {
            current_line_len += 1;
        }
    }
    max_line_len = @max(max_line_len, current_line_len);

    // Account for word wrapping
    const content_width = @min(@as(u16, @intCast(max_line_len)), config.max_width);
    const content_height = @min(@as(u16, @intCast(line_count)), config.max_height);

    // Add border space
    const border_space: u16 = if (config.border != .none) 2 else 0;

    return .{
        .width = content_width + border_space,
        .height = content_height + border_space,
    };
}
