//! Status line rendering
//! Shows mode, file info, cursor position, and selections

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;
const diagnostics_render = @import("diagnostics.zig");

const Editor = @import("../editor/editor.zig").Editor;
const Mode = @import("../editor/mode.zig").Mode;
const Theme = @import("../editor/theme.zig").Theme;

/// Render status line at bottom of screen
pub fn render(rend: *renderer.Renderer, editor: *const Editor) !void {
    const theme = editor.getTheme();
    const size = rend.getSize();
    const status_row = size.height - 1;

    // Get status info from editor
    const info = editor.getStatusInfo();

    // Clear status line
    var col: u16 = 0;
    while (col < size.width) : (col += 1) {
        rend.output.setCell(status_row, col, .{
            .char = ' ',
            .fg = theme.ui.statusline_fg,
            .bg = theme.ui.statusline_bg,
            .attrs = .{},
        });
    }

    // Left section: Mode
    const mode_bg = getModeColor(info.mode, theme);
    const mode_fg = getModeFgColor(info.mode, theme);
    const mode_text = info.mode.name();

    rend.writeText(
        status_row,
        1,
        mode_text,
        mode_fg,
        mode_bg,
        .{ .bold = true },
    );

    col = @intCast(mode_text.len + 2);

    // Buffer name and modified indicator
    // Use full path if available, otherwise just the name
    const display_name = if (info.file_path) |path| path else info.buffer_name;

    // Truncate path if too long (leave room for other info)
    const max_path_len = if (size.width > 80) size.width / 2 else 30;
    const truncated_name = if (display_name.len > max_path_len)
        display_name[display_name.len - max_path_len ..]
    else
        display_name;

    var buf: [512]u8 = undefined;
    const buffer_info = std.fmt.bufPrint(
        &buf,
        " {s}{s}{s}",
        .{
            truncated_name,
            if (info.modified) " [+]" else "",
            if (info.readonly) " [RO]" else "",
        },
    ) catch "";

    rend.writeText(
        status_row,
        col,
        buffer_info,
        theme.ui.statusline_fg,
        theme.ui.statusline_bg,
        .{},
    );

    // Right section: Cursor position, percentage, and line count
    const pos_text = std.fmt.bufPrint(
        &buf,
        " {d}:{d} {d}% {d}/{d} ",
        .{ info.line, info.col, info.percent, info.line, info.total_lines },
    ) catch "";

    const pos_col = size.width -| @as(u16, @intCast(pos_text.len));
    rend.writeText(
        status_row,
        pos_col,
        pos_text,
        theme.ui.statusline_fg,
        theme.ui.statusline_bg,
        .{},
    );

    // Diagnostic counts (before position)
    const counts = editor.diagnostic_manager.getCountsBySeverity();
    const diag_text = diagnostics_render.formatDiagnosticCounts(
        editor.allocator,
        counts.errors,
        counts.warnings,
        counts.info,
        counts.hints,
    ) catch "";
    defer if (diag_text.len > 0) editor.allocator.free(diag_text);

    var next_col = pos_col;
    if (diag_text.len > 0) {
        const diag_col = pos_col -| @as(u16, @intCast(diag_text.len + 2));
        rend.writeText(
            status_row,
            diag_col,
            " ",
            theme.ui.statusline_fg,
            theme.ui.statusline_bg,
            .{},
        );
        rend.writeText(
            status_row,
            diag_col + 1,
            diag_text,
            if (counts.errors > 0)
                theme.ui.diagnostic_error
            else if (counts.warnings > 0)
                theme.ui.diagnostic_warning
            else
                theme.ui.diagnostic_info,
            theme.ui.statusline_bg,
            if (counts.errors > 0) .{ .bold = true } else .{},
        );
        next_col = diag_col;
    }

    // Undo/redo indicators (before diagnostics)
    var undo_text_buf: [16]u8 = undefined;
    const undo_text = std.fmt.bufPrint(
        &undo_text_buf,
        "{s}{s}",
        .{
            if (info.can_undo) " u" else "",
            if (info.can_redo) " U" else "",
        },
    ) catch "";

    if (undo_text.len > 0) {
        const undo_col = next_col -| @as(u16, @intCast(undo_text.len + 1));
        rend.writeText(
            status_row,
            undo_col,
            undo_text,
            theme.palette.accent_cyan,
            theme.ui.statusline_bg,
            .{},
        );
    }

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
            theme.palette.foreground,
            theme.palette.accent_purple,
            .{ .bold = true },
        );
    }
}

fn getModeColor(mode: Mode, theme: *const Theme) Color {
    return switch (mode) {
        .normal => theme.ui.statusline_mode_normal_bg,
        .insert => theme.ui.statusline_mode_insert_bg,
        .select => theme.ui.statusline_mode_select_bg,
        .command => theme.ui.statusline_mode_command_bg,
    };
}

fn getModeFgColor(mode: Mode, theme: *const Theme) Color {
    return switch (mode) {
        .normal => theme.ui.statusline_mode_normal_fg,
        .insert => theme.ui.statusline_mode_insert_fg,
        .select => theme.ui.statusline_mode_select_fg,
        .command => theme.ui.statusline_mode_command_fg,
    };
}
