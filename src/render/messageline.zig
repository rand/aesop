//! Message line rendering
//! Shows info, warning, error, and success messages above status line

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const Message = @import("../editor/message.zig");

/// Render message line above status line (if message exists)
pub fn render(rend: *renderer.Renderer, editor: *const Editor) !bool {
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
            .fg = .{ .standard = .white },
            .bg = getLevelBgColor(current_msg.level),
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
        getLevelFgColor(current_msg.level),
        getLevelBgColor(current_msg.level),
        .{ .bold = true },
    );

    return true; // Message was displayed
}

fn getLevelFgColor(level: Message.Level) Color {
    return switch (level) {
        .info => .{ .standard = .white },
        .warning => .{ .standard = .black },
        .error_msg => .{ .standard = .white },
        .success => .{ .standard = .black },
    };
}

fn getLevelBgColor(level: Message.Level) Color {
    return switch (level) {
        .info => .{ .standard = .blue },
        .warning => .{ .standard = .yellow },
        .error_msg => .{ .standard = .red },
        .success => .{ .standard = .green },
    };
}
