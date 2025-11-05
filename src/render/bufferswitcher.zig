//! Buffer switcher rendering
//! Displays open buffers as an overlay for quick navigation

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const BufferManager = @import("../editor/../buffer/manager.zig");

const BufferId = @import("../buffer/manager.zig").BufferId;

/// Buffer info for display
pub const BufferInfo = struct {
    id: BufferId,
    name: []const u8,
    modified: bool,
    active: bool,
};

/// Render buffer switcher overlay (centered popup)
pub fn render(rend: *renderer.Renderer, editor: *Editor, allocator: std.mem.Allocator, visible: bool, selected_index: usize) !void {
    if (!visible) return;

    const size = rend.getSize();

    // Get list of open buffers
    const buffers = try getBufferList(editor, allocator);
    defer allocator.free(buffers);

    if (buffers.len == 0) return; // No buffers to show

    // Calculate switcher dimensions
    const switcher_height: u16 = @min(@as(u16, @intCast(buffers.len + 2)), size.height -| 4); // +2 for border and title
    const switcher_width: u16 = @min(60, size.width -| 4);

    // Center the switcher
    const start_row = (size.height -| switcher_height) / 2;
    const start_col = (size.width -| switcher_width) / 2;

    // Draw background box
    var row: u16 = 0;
    while (row < switcher_height) : (row += 1) {
        var col: u16 = 0;
        while (col < switcher_width) : (col += 1) {
            rend.output.setCell(start_row + row, start_col + col, .{
                .char = ' ',
                .fg = .{ .standard = .white },
                .bg = .{ .standard = .black },
                .attrs = .{},
            });
        }
    }

    // Draw border
    drawBorder(rend, start_row, start_col, switcher_width, switcher_height);

    // Draw title
    const title = " Open Buffers ";
    const title_col = start_col + (switcher_width -| @as(u16, @intCast(title.len))) / 2;
    rend.writeText(start_row, title_col, title, .{ .standard = .blue }, .{ .standard = .black }, .{ .bold = true }, null);

    // Draw buffer list
    const max_items: u16 = switcher_height -| 2; // Subtract border and title
    const visible_buffers = @min(buffers.len, max_items);

    var i: usize = 0;
    while (i < visible_buffers) : (i += 1) {
        const buffer_info = buffers[i];
        const is_selected = i == selected_index;

        const item_row = start_row + 1 + @as(u16, @intCast(i));

        // Highlight selected item
        if (is_selected) {
            var col: u16 = 1;
            while (col < switcher_width - 1) : (col += 1) {
                rend.output.setCell(item_row, start_col + col, .{
                    .char = ' ',
                    .fg = .{ .standard = .black },
                    .bg = .{ .standard = .blue },
                    .attrs = .{},
                });
            }
        }

        // Format buffer entry
        var item_buf: [256]u8 = undefined;
        const modified_marker = if (buffer_info.modified) " [+]" else "";
        const active_marker = if (buffer_info.active) " *" else "";

        const item_text = std.fmt.bufPrint(
            &item_buf,
            " {s}{s}{s}",
            .{ buffer_info.name, modified_marker, active_marker },
        ) catch "";

        const fg = if (is_selected) Color{ .standard = .black } else Color{ .standard = .white };
        const bg = if (is_selected) Color{ .standard = .blue } else Color{ .standard = .black };

        rend.writeText(item_row, start_col + 1, item_text[0..@min(item_text.len, switcher_width - 2)], fg, bg, if (is_selected) .{ .bold = true } else .{}, null);
    }

    // Show count
    if (buffers.len > 0) {
        var count_buf: [32]u8 = undefined;
        const count_text = std.fmt.bufPrint(
            &count_buf,
            " {d}/{d} ",
            .{ selected_index + 1, buffers.len },
        ) catch "";

        const count_col = start_col + switcher_width -| @as(u16, @intCast(count_text.len)) - 1;
        rend.writeText(start_row + switcher_height - 1, count_col, count_text, .{ .standard = .blue }, .{ .standard = .black }, .{}, null);
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

/// Get list of open buffers for display
pub fn getBufferList(editor: *Editor, allocator: std.mem.Allocator) ![]BufferInfo {
    var list = std.ArrayList(BufferInfo).empty;
    errdefer list.deinit(allocator);

    // Iterate through all buffers
    for (editor.buffer_manager.buffers.items) |buffer| {
        const buffer_id = buffer.metadata.id;

        const is_active = if (editor.buffer_manager.active_buffer_id) |active_id|
            active_id == buffer_id
        else
            false;

        try list.append(allocator, .{
            .id = buffer_id,
            .name = buffer.metadata.getName(),
            .modified = buffer.metadata.modified,
            .active = is_active,
        });
    }

    return list.toOwnedSlice(allocator);
}
