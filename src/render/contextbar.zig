//! Context bar rendering
//! Shows mode-specific contextual hints and guidance

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const Mode = @import("../editor/mode.zig").Mode;
const Theme = @import("../editor/theme.zig").Theme;

/// Hint item - represents a single actionable hint
const Hint = struct {
    key: []const u8, // The key/shortcut
    action: []const u8, // What it does
    color: Color, // Color for the key
    priority: u8, // Higher = more important (0-9)

    pub fn format(
        self: Hint,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}:{s}", .{ self.key, self.action });
    }
};

/// Context types - determines which hints to show
const Context = enum {
    empty_buffer_normal,
    normal_mode,
    insert_mode,
    select_mode,
    command_mode,
    incremental_search,
    palette_open,
    file_finder_open,
    buffer_switcher_open,
    pending_command,
};

/// Detect current context from editor state
fn detectContext(editor: *const Editor, is_empty_buffer: bool) Context {
    // Priority order: overlays > special states > modes

    // Check overlays first
    if (editor.palette.visible) return .palette_open;
    if (editor.file_finder.visible) return .file_finder_open;
    if (editor.buffer_switcher_visible) return .buffer_switcher_open;

    // Check special states
    if (editor.search.incremental) return .incremental_search;
    if (editor.pending_command.isWaiting()) return .pending_command;

    // Check modes
    const mode = editor.getMode();
    return switch (mode) {
        .normal => if (is_empty_buffer) .empty_buffer_normal else .normal_mode,
        .insert => .insert_mode,
        .select => .select_mode,
        .command => .command_mode,
    };
}

/// Get hints for a specific context
fn getHintsForContext(context: Context, theme: *const Theme, allocator: std.mem.Allocator) ![]const Hint {
    const cyan = theme.palette.accent_cyan;
    const teal = theme.palette.accent_teal;
    const pink = theme.palette.accent_pink;
    const purple = theme.palette.accent_purple;
    const white = theme.palette.foreground;

    const hints = switch (context) {
        .empty_buffer_normal => &[_]Hint{
            .{ .key = "i", .action = "insert", .color = cyan, .priority = 9 },
            .{ .key = ":", .action = "command", .color = cyan, .priority = 8 },
            .{ .key = "Space p", .action = "palette", .color = teal, .priority = 7 },
            .{ .key = "Space f", .action = "files", .color = teal, .priority = 6 },
            .{ .key = ":q", .action = "quit", .color = pink, .priority = 5 },
            .{ .key = "?", .action = "help", .color = purple, .priority = 4 },
        },

        .normal_mode => &[_]Hint{
            .{ .key = "i", .action = "insert", .color = cyan, .priority = 9 },
            .{ .key = "v", .action = "select", .color = cyan, .priority = 8 },
            .{ .key = "/", .action = "search", .color = cyan, .priority = 7 },
            .{ .key = "Space p", .action = "palette", .color = teal, .priority = 6 },
            .{ .key = "Space f", .action = "files", .color = teal, .priority = 5 },
            .{ .key = "Space b", .action = "buffers", .color = teal, .priority = 4 },
            .{ .key = "u", .action = "undo", .color = purple, .priority = 3 },
            .{ .key = "dd", .action = "delete-line", .color = pink, .priority = 2 },
            .{ .key = ":q", .action = "quit", .color = pink, .priority = 1 },
        },

        .insert_mode => &[_]Hint{
            .{ .key = "ESC", .action = "normal", .color = cyan, .priority = 9 },
            .{ .key = "Typing", .action = "edit text", .color = white, .priority = 8 },
            .{ .key = "←↓↑→", .action = "move", .color = white, .priority = 7 },
            .{ .key = "Backspace", .action = "delete", .color = white, .priority = 6 },
            .{ .key = "Enter", .action = "newline", .color = white, .priority = 5 },
            .{ .key = "Ctrl+Q", .action = "force-quit", .color = pink, .priority = 4 },
        },

        .select_mode => &[_]Hint{
            .{ .key = "d", .action = "delete", .color = pink, .priority = 9 },
            .{ .key = "y", .action = "yank", .color = purple, .priority = 8 },
            .{ .key = "hjkl", .action = "extend", .color = cyan, .priority = 7 },
            .{ .key = "ESC", .action = "normal", .color = cyan, .priority = 6 },
            .{ .key = "w/b/e", .action = "word-select", .color = cyan, .priority = 5 },
            .{ .key = "0/$", .action = "line-ends", .color = cyan, .priority = 4 },
        },

        .command_mode => &[_]Hint{
            .{ .key = "Enter", .action = "execute", .color = teal, .priority = 9 },
            .{ .key = "ESC", .action = "cancel", .color = pink, .priority = 8 },
            .{ .key = ":w", .action = "save", .color = purple, .priority = 7 },
            .{ .key = ":q", .action = "quit", .color = purple, .priority = 6 },
            .{ .key = ":wq", .action = "save-quit", .color = purple, .priority = 5 },
            .{ .key = ":e", .action = "open-file", .color = purple, .priority = 4 },
        },

        .incremental_search => &[_]Hint{
            .{ .key = "Type", .action = "search", .color = purple, .priority = 9 },
            .{ .key = "Enter", .action = "confirm", .color = teal, .priority = 8 },
            .{ .key = "ESC", .action = "cancel", .color = pink, .priority = 7 },
            .{ .key = "n", .action = "next", .color = cyan, .priority = 6 },
            .{ .key = "N", .action = "previous", .color = cyan, .priority = 5 },
            .{ .key = "Backspace", .action = "edit", .color = white, .priority = 4 },
        },

        .palette_open => &[_]Hint{
            .{ .key = "Type", .action = "filter", .color = purple, .priority = 9 },
            .{ .key = "Enter", .action = "execute", .color = teal, .priority = 8 },
            .{ .key = "ESC", .action = "close", .color = pink, .priority = 7 },
            .{ .key = "↑↓", .action = "navigate", .color = cyan, .priority = 6 },
            .{ .key = "Backspace", .action = "edit", .color = white, .priority = 5 },
        },

        .file_finder_open => &[_]Hint{
            .{ .key = "Type", .action = "search-path", .color = purple, .priority = 9 },
            .{ .key = "Enter", .action = "open", .color = teal, .priority = 8 },
            .{ .key = "ESC", .action = "close", .color = pink, .priority = 7 },
            .{ .key = "↑↓", .action = "navigate", .color = cyan, .priority = 6 },
            .{ .key = "Backspace", .action = "edit", .color = white, .priority = 5 },
        },

        .buffer_switcher_open => &[_]Hint{
            .{ .key = "↑↓", .action = "select", .color = cyan, .priority = 9 },
            .{ .key = "Enter", .action = "switch", .color = teal, .priority = 8 },
            .{ .key = "ESC", .action = "close", .color = pink, .priority = 7 },
            .{ .key = "Space c", .action = "close-buffer", .color = purple, .priority = 6 },
        },

        .pending_command => &[_]Hint{
            .{ .key = "w", .action = "word", .color = cyan, .priority = 9 },
            .{ .key = "d", .action = "line", .color = cyan, .priority = 8 },
            .{ .key = "$", .action = "to-end", .color = cyan, .priority = 7 },
            .{ .key = "0", .action = "to-start", .color = cyan, .priority = 6 },
            .{ .key = "ESC", .action = "cancel", .color = pink, .priority = 5 },
        },
    };

    // Allocate and copy hints
    const result = try allocator.alloc(Hint, hints.len);
    @memcpy(result, hints);
    return result;
}

/// Select hints based on terminal width
fn selectHintsByWidth(hints: []const Hint, width: u16) []const Hint {
    // Sort by priority (already sorted in getHintsForContext)
    // Select top N based on width
    const max_hints = if (width < 80)
        @min(3, hints.len)
    else if (width < 120)
        @min(6, hints.len)
    else
        hints.len;

    return hints[0..max_hints];
}

/// Calculate total width needed for hints with separators
fn calculateHintWidth(hints: []const Hint) usize {
    var total: usize = 0;
    for (hints, 0..) |hint, i| {
        // key:action format
        total += hint.key.len + 1 + hint.action.len;
        // Add separator width (except for last)
        if (i < hints.len - 1) {
            total += 3; // " | "
        }
    }
    return total + 2; // +2 for leading/trailing spaces
}

/// Render context bar at bottom of screen (above status line)
pub fn render(rend: *renderer.Renderer, editor: *const Editor, is_empty_buffer: bool, allocator: std.mem.Allocator) !void {
    const theme = editor.getTheme();
    const size = rend.getSize();
    const context_row = size.height - 2; // One line above status line
    const bg_color = theme.ui.contextbar_bg;

    // Clear context bar line
    var col: u16 = 0;
    while (col < size.width) : (col += 1) {
        rend.output.setCell(context_row, col, .{
            .char = ' ',
            .fg = .default,
            .bg = bg_color,
            .attrs = .{},
        });
    }

    // Detect context
    const context = detectContext(editor, is_empty_buffer);

    // Get hints for context
    const all_hints = try getHintsForContext(context, theme, allocator);
    defer allocator.free(all_hints);

    // Select hints based on width
    const hints = selectHintsByWidth(all_hints, size.width);

    // Calculate total width
    const hint_width = calculateHintWidth(hints);

    // Center hints if they fit, otherwise left-align with padding
    const start_col = if (hint_width < size.width)
        @as(u16, @intCast((size.width - hint_width) / 2))
    else
        1;

    // Render hints
    var current_col = start_col;
    for (hints, 0..) |hint, i| {
        // Render key (bold, colored)
        rend.writeText(
            context_row,
            current_col,
            hint.key,
            hint.color,
            bg_color,
            .{ .bold = true }, null);
        current_col += @intCast(hint.key.len);

        // Render colon
        rend.writeText(
            context_row,
            current_col,
            ":",
            theme.ui.contextbar_fg,
            bg_color,
            .{}, null);
        current_col += 1;

        // Render action
        rend.writeText(
            context_row,
            current_col,
            hint.action,
            theme.ui.contextbar_fg,
            bg_color,
            .{}, null);
        current_col += @intCast(hint.action.len);

        // Render separator (except for last)
        if (i < hints.len - 1) {
            rend.writeText(
                context_row,
                current_col,
                " | ",
                theme.ui.contextbar_separator,
                bg_color,
                .{}, null);
            current_col += 3;
        }
    }

    // Special case: empty buffer - add welcome message on left
    if (context == .empty_buffer_normal) {
        const welcome = "Welcome to Aesop!";
        rend.writeText(
            context_row,
            2,
            welcome,
            theme.ui.contextbar_welcome,
            bg_color,
            .{ .bold = true }, null);
    }
}
