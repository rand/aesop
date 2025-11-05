//! Key hints rendering
//! Shows pending key sequences and available commands

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;

/// Render key hints in bottom-right of status line
pub fn render(rend: *renderer.Renderer, editor: *const Editor) !void {
    const size = rend.getSize();
    const status_row = size.height - 1;

    // Check if there are pending keys
    if (!editor.keymap_manager.hasPending()) {
        return; // No hints to show
    }

    // Get pending key sequence
    const pending = editor.keymap_manager.pending_keys.constSlice();
    if (pending.len == 0) return;

    // Format pending keys
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.writeAll(" [") catch return;

    for (pending, 0..) |key, i| {
        if (i > 0) writer.writeAll(" ") catch return;

        switch (key) {
            .char => |c| {
                if (c >= 32 and c < 127) {
                    writer.writeByte(@intCast(c)) catch return;
                } else {
                    writer.print("U+{X}", .{c}) catch return;
                }
            },
            .special => |s| {
                writer.print("<{s}>", .{@tagName(s)}) catch return;
            },
        }
    }

    writer.writeAll("...] ") catch return;

    const hint_text = fbs.getWritten();

    // Calculate position (right side of status line)
    const hint_col = size.width -| @as(u16, @intCast(hint_text.len));

    // Render hints
    rend.writeText(status_row, hint_col, hint_text, .{ .standard = .yellow }, .{ .standard = .blue }, .{ .italic = true }, null);
}
