//! Status line rendering
//! Shows mode, file info, cursor position, and selections

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const Mode = @import("../editor/mode.zig").Mode;

/// Render status line at bottom of screen
pub fn render(rend: *renderer.Renderer, editor: *const Editor) !void {
    const size = rend.getSize();
    const status_row = size.height - 1;

    // Get status info from editor
    const info = editor.getStatusInfo();

    // Clear status line
    var col: u16 = 0;
    while (col < size.width) : (col += 1) {
        rend.output.setCell(status_row, col, .{
            .char = ' ',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .blue },
            .attrs = .{},
        });
    }

    // Left section: Mode
    const mode_color = getModeColor(info.mode);
    const mode_text = info.mode.name();

    rend.writeText(
        status_row,
        1,
        mode_text,
        .{ .standard = .black },
        mode_color,
        .{ .bold = true },
    );

    col = @intCast(mode_text.len + 2);

    // Buffer name and modified indicator
    var buf: [256]u8 = undefined;
    const buffer_info = std.fmt.bufPrint(
        &buf,
        " {s}{s}{s}",
        .{
            info.buffer_name,
            if (info.modified) " [+]" else "",
            if (info.readonly) " [RO]" else "",
        },
    ) catch "";

    rend.writeText(
        status_row,
        col,
        buffer_info,
        .{ .standard = .white },
        .{ .standard = .blue },
        .{},
    );

    // Right section: Cursor position and line count
    const pos_text = std.fmt.bufPrint(
        &buf,
        " {d}:{d} {d}/{d} ",
        .{ info.line, info.col, info.line, info.total_lines },
    ) catch "";

    const pos_col = size.width -| @as(u16, @intCast(pos_text.len));
    rend.writeText(
        status_row,
        pos_col,
        pos_text,
        .{ .standard = .white },
        .{ .standard = .blue },
        .{},
    );

    // Selection count if multiple
    if (info.selection_count > 1) {
        const sel_text = std.fmt.bufPrint(
            &buf,
            " {d} sel ",
            .{info.selection_count},
        ) catch "";

        const sel_col = pos_col -| @as(u16, @intCast(sel_text.len));
        rend.writeText(
            status_row,
            sel_col,
            sel_text,
            .{ .standard = .black },
            .{ .standard = .yellow },
            .{ .bold = true },
        );
    }
}

fn getModeColor(mode: Mode) Color {
    return switch (mode) {
        .normal => .{ .standard = .green },
        .insert => .{ .standard = .blue },
        .select => .{ .standard = .magenta },
        .command => .{ .standard = .cyan },
    };
}
