//! Message line rendering
//! Shows info, warning, error, and success messages above status line

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const Message = @import("../editor/message.zig");
const Theme = @import("../editor/theme.zig").Theme;

/// Render message line above status line (if message exists)
pub fn render(rend: *renderer.Renderer, editor: *const Editor) !bool {
    const theme = editor.getTheme();
    const size = rend.getSize();
    const message_row = size.height - 2; // Above status line

    // Get current message from editor
    var queue = editor.messages;
    const msg = queue.current();

    if (msg == null) {
        return false; // No message to display
    }

    const current_msg = msg.?;

    // Clear message line
    var col: u16 = 0;
    while (col < size.width) : (col += 1) {
        rend.output.setCell(message_row, col, .{
            .char = ' ',
            .fg = getLevelFgColor(current_msg.level, theme),
            .bg = getLevelBgColor(current_msg.level, theme),
            .attrs = .{},
        });
    }

    // Format message with level prefix
    var buf: [512]u8 = undefined;
    const message_text = std.fmt.bufPrint(
        &buf,
        " {s}: {s} ",
        .{ current_msg.level.name(), current_msg.content },
    ) catch return false;

    // Truncate if too long
    const display_len = @min(message_text.len, size.width);

    rend.writeText(
        message_row,
        0,
        message_text[0..display_len],
        getLevelFgColor(current_msg.level, theme),
        getLevelBgColor(current_msg.level, theme),
        .{ .bold = true }, null);

    return true; // Message was displayed
}

fn getLevelFgColor(level: Message.Level, theme: *const Theme) Color {
    return switch (level) {
        .info => theme.ui.message_info_fg,
        .warning => theme.ui.message_warning_fg,
        .error_msg => theme.ui.message_error_fg,
        .success => theme.palette.success,
    };
}

fn getLevelBgColor(level: Message.Level, theme: *const Theme) Color {
    return switch (level) {
        .info => theme.ui.message_info_bg,
        .warning => theme.ui.message_warning_bg,
        .error_msg => theme.ui.message_error_bg,
        .success => theme.palette.background_lighter,
    };
}
