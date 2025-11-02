//! Command palette rendering
//! Displays filtered command list as an overlay

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const Palette = @import("../editor/palette.zig");

/// Render command palette overlay (centered popup)
pub fn render(rend: *renderer.Renderer, editor: *Editor, allocator: std.mem.Allocator) !void {
    if (!editor.palette.visible) return;

    const size = rend.getSize();

    // Get filtered commands
    const matches = try editor.palette.filterCommands(&editor.command_registry, allocator);
    defer allocator.free(matches);

    // Calculate palette dimensions
    const palette_height: u16 = @min(@as(u16, @intCast(matches.len + 3)), size.height -| 4); // +3 for border and query
    const palette_width: u16 = @min(60, size.width -| 4);

    // Center the palette
    const start_row = (size.height -| palette_height) / 2;
    const start_col = (size.width -| palette_width) / 2;

    // Draw background box
    var row: u16 = 0;
    while (row < palette_height) : (row += 1) {
        var col: u16 = 0;
        while (col < palette_width) : (col += 1) {
            rend.output.setCell(start_row + row, start_col + col, .{
                .char = ' ',
                .fg = .{ .standard = .white },
                .bg = .{ .standard = .black },
                .attrs = .{},
            });
        }
    }

    // Draw border
    drawBorder(rend, start_row, start_col, palette_width, palette_height);

    // Draw title
    const title = " Command Palette ";
    const title_col = start_col + (palette_width -| @as(u16, @intCast(title.len))) / 2;
    rend.writeText(
        start_row,
        title_col,
        title,
        .{ .standard = .cyan },
        .{ .standard = .black },
        .{ .bold = true },
    );

    // Draw query line
    var query_buf: [64]u8 = undefined;
    const query_text = std.fmt.bufPrint(
        &query_buf,
        " > {s}",
        .{editor.palette.getQuery()},
    ) catch " > ";

    rend.writeText(
        start_row + 1,
        start_col + 1,
        query_text,
        .{ .standard = .yellow },
        .{ .standard = .black },
        .{},
    );

    // Draw separator
    var sep_col: u16 = 1;
    while (sep_col < palette_width - 1) : (sep_col += 1) {
        rend.output.setCell(start_row + 2, start_col + sep_col, .{
            .char = '─',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }

    // Draw command list
    const max_items: u16 = palette_height -| 4; // Subtract border, query, separator
    const visible_matches = @min(matches.len, max_items);

    var i: usize = 0;
    while (i < visible_matches) : (i += 1) {
        const match = matches[i];
        const is_selected = i == editor.palette.selected_index;

        const item_row = start_row + 3 + @as(u16, @intCast(i));

        // Highlight selected item
        if (is_selected) {
            var col: u16 = 1;
            while (col < palette_width - 1) : (col += 1) {
                rend.output.setCell(item_row, start_col + col, .{
                    .char = ' ',
                    .fg = .{ .standard = .black },
                    .bg = .{ .standard = .cyan },
                    .attrs = .{},
                });
            }
        }

        // Format command entry
        var item_buf: [128]u8 = undefined;
        const item_text = std.fmt.bufPrint(
            &item_buf,
            " {s}",
            .{match.name},
        ) catch "";

        const fg = if (is_selected) Color{ .standard = .black } else Color{ .standard = .white };
        const bg = if (is_selected) Color{ .standard = .cyan } else Color{ .standard = .black };

        rend.writeText(
            item_row,
            start_col + 1,
            item_text[0..@min(item_text.len, palette_width - 2)],
            fg,
            bg,
            if (is_selected) .{ .bold = true } else .{},
        );
    }

    // Show count
    if (matches.len > 0) {
        var count_buf: [32]u8 = undefined;
        const count_text = std.fmt.bufPrint(
            &count_buf,
            " {d}/{d} ",
            .{ editor.palette.selected_index + 1, matches.len },
        ) catch "";

        const count_col = start_col + palette_width -| @as(u16, @intCast(count_text.len)) - 1;
        rend.writeText(
            start_row + palette_height - 1,
            count_col,
            count_text,
            .{ .standard = .cyan },
            .{ .standard = .black },
            .{},
        );
    }
}

fn drawBorder(rend: *renderer.Renderer, row: u16, col: u16, width: u16, height: u16) void {
    // Top-left corner
    rend.output.setCell(row, col, .{
        .char = '┌',
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });

    // Top-right corner
    rend.output.setCell(row, col + width - 1, .{
        .char = '┐',
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });

    // Bottom-left corner
    rend.output.setCell(row + height - 1, col, .{
        .char = '└',
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });

    // Bottom-right corner
    rend.output.setCell(row + height - 1, col + width - 1, .{
        .char = '┘',
        .fg = .{ .standard = .white },
        .bg = .{ .standard = .black },
        .attrs = .{},
    });

    // Top and bottom borders
    var c: u16 = 1;
    while (c < width - 1) : (c += 1) {
        rend.output.setCell(row, col + c, .{
            .char = '─',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
        rend.output.setCell(row + height - 1, col + c, .{
            .char = '─',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }

    // Left and right borders
    var r: u16 = 1;
    while (r < height - 1) : (r += 1) {
        rend.output.setCell(row + r, col, .{
            .char = '│',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
        rend.output.setCell(row + r, col + width - 1, .{
            .char = '│',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }
}
