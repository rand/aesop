//! Code completion popup rendering
//! Displays completion suggestions near cursor position

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const Completion = @import("../editor/completion.zig");
const CompletionList = Completion.CompletionList;
const CompletionItem = Completion.CompletionItem;

/// Render completion popup near cursor
pub fn render(rend: *renderer.Renderer, _: *Editor, completion_list: *const CompletionList) !void {
    if (!completion_list.visible) return;
    if (completion_list.getFilteredCount() == 0) return;

    const size = rend.getSize();
    const cursor_line = completion_list.trigger_pos.line;
    const cursor_col = completion_list.trigger_pos.col;

    // Calculate popup dimensions
    const max_items: usize = 10; // Show up to 10 items at a time
    const item_count = @min(completion_list.getFilteredCount(), max_items);
    const popup_height: u16 = @intCast(item_count + 2); // +2 for borders
    const popup_width: u16 = 40; // Fixed width for now

    // Position popup below cursor (or above if not enough space)
    var start_row: u16 = @intCast(@min(cursor_line + 1, size.height -| popup_height));
    const start_col: u16 = @intCast(@min(cursor_col, size.width -| popup_width));

    // If cursor is in bottom half of screen, show popup above cursor
    if (cursor_line > size.height / 2 and cursor_line >= popup_height) {
        start_row = @intCast(cursor_line -| popup_height);
    }

    // Draw background box
    var row: u16 = 0;
    while (row < popup_height) : (row += 1) {
        var col: u16 = 0;
        while (col < popup_width) : (col += 1) {
            rend.output.setCell(start_row + row, start_col + col, .{
                .char = ' ',
                .fg = .{ .standard = .white },
                .bg = .{ .standard = .black },
                .attrs = .{},
            });
        }
    }

    // Draw border
    drawBorder(rend, start_row, start_col, popup_width, popup_height);

    // Draw completion items
    var i: usize = 0;
    while (i < item_count) : (i += 1) {
        const item_index = completion_list.filtered_indices.items[i];
        const item = &completion_list.items.items[item_index];
        const is_selected = i == completion_list.selected_index;

        const item_row = start_row + 1 + @as(u16, @intCast(i));

        // Highlight selected item background
        if (is_selected) {
            var col: u16 = 1;
            while (col < popup_width - 1) : (col += 1) {
                rend.output.setCell(item_row, start_col + col, .{
                    .char = ' ',
                    .fg = .{ .standard = .black },
                    .bg = .{ .standard = .cyan },
                    .attrs = .{},
                });
            }
        }

        // Draw icon based on completion kind
        const icon = item.kind.icon();
        rend.writeText(item_row, start_col + 1, icon, if (is_selected) .{ .standard = .black } else .{ .standard = .cyan }, if (is_selected) .{ .standard = .cyan } else .{ .standard = .black }, .{ .bold = true }, null);

        // Draw label
        const max_label_len = popup_width -| 5; // Reserve space for icon and padding
        const label = if (item.label.len > max_label_len)
            item.label[0..max_label_len]
        else
            item.label;

        rend.writeText(item_row, start_col + 3, label, if (is_selected) .{ .standard = .black } else .{ .standard = .white }, if (is_selected) .{ .standard = .cyan } else .{ .standard = .black }, .{}, null);

        // Draw type hint if available and space permits
        if (item.detail) |detail| {
            const type_col = start_col + 3 + @as(u16, @intCast(label.len)) + 1;
            if (type_col < start_col + popup_width - 2) {
                const max_detail_len = (start_col + popup_width - 2) -| type_col;
                const detail_text = if (detail.len > max_detail_len)
                    detail[0..max_detail_len]
                else
                    detail;

                rend.writeText(item_row, type_col, detail_text, if (is_selected) .{ .standard = .black } else .{ .standard = .bright_black }, if (is_selected) .{ .standard = .cyan } else .{ .standard = .black }, .{}, null);
            }
        }
    }

    // Draw scroll indicator if more items available
    if (completion_list.getFilteredCount() > item_count) {
        const scroll_row = start_row + popup_height - 1;
        var scroll_text_buf: [16]u8 = undefined;
        const scroll_text = std.fmt.bufPrint(
            &scroll_text_buf,
            " {}/{} ",
            .{ completion_list.selected_index + 1, completion_list.getFilteredCount() },
        ) catch " ... ";

        const scroll_col = start_col + popup_width - @as(u16, @intCast(scroll_text.len)) - 1;
        rend.writeText(scroll_row, scroll_col, scroll_text, .{ .standard = .bright_black }, .{ .standard = .black }, .{}, null);
    }
}

/// Draw box border
fn drawBorder(rend: *renderer.Renderer, row: u16, col: u16, width: u16, height: u16) void {
    // Top border
    rend.output.setCell(row, col, .{
        .char = '┌',
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });
    var x: u16 = 1;
    while (x < width - 1) : (x += 1) {
        rend.output.setCell(row, col + x, .{
            .char = '─',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }
    rend.output.setCell(row, col + width - 1, .{
        .char = '┐',
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });

    // Side borders
    var y: u16 = 1;
    while (y < height - 1) : (y += 1) {
        rend.output.setCell(row + y, col, .{
            .char = '│',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
        rend.output.setCell(row + y, col + width - 1, .{
            .char = '│',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }

    // Bottom border
    rend.output.setCell(row + height - 1, col, .{
        .char = '└',
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });
    x = 1;
    while (x < width - 1) : (x += 1) {
        rend.output.setCell(row + height - 1, col + x, .{
            .char = '─',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }
    rend.output.setCell(row + height - 1, col + width - 1, .{
        .char = '┘',
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });
}
