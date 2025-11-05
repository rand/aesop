//! File tree rendering
//! Displays directory tree as a sidebar

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const FileTree = @import("../editor/file_tree.zig").FileTree;
const TreeNode = @import("../editor/file_tree.zig").TreeNode;

/// Render file tree as left sidebar
pub fn render(rend: *renderer.Renderer, editor: *Editor, allocator: std.mem.Allocator) !void {
    _ = allocator;
    if (!editor.file_tree.visible) return;

    const theme = editor.getTheme();
    const size = rend.getSize();
    const tree_width = editor.file_tree.width;

    // Don't render if tree is wider than screen
    if (tree_width >= size.width) return;

    // Calculate visible height (exclude status bars)
    const visible_height = size.height -| 3; // status + context + message

    // Render tree background
    var row: u16 = 0;
    while (row < visible_height) : (row += 1) {
        var col: u16 = 0;
        while (col < tree_width) : (col += 1) {
            rend.output.setCell(row, col, .{
                .char = ' ',
                .fg = theme.ui.tree_fg,
                .bg = theme.ui.tree_bg,
                .attrs = .{},
            });
        }

        // Draw vertical separator
        const style = IconStyle.detect();
        const border_char: u21 = switch (style) {
            .nerd_font => 0x2502, // '│' - Box-drawing character
            .ascii => '|',
        };
        rend.output.setCell(row, tree_width, .{
            .char = border_char,
            .fg = theme.ui.tree_border,
            .bg = theme.ui.tree_bg,
            .attrs = .{},
        });
    }

    // Render tree title
    const title = " File Explorer ";
    if (title.len < tree_width) {
        const title_col = (tree_width - @as(u16, @intCast(title.len))) / 2;
        rend.writeText(
            0,
            title_col,
            title,
            theme.ui.tree_title,
            theme.ui.tree_bg,
            .{ .bold = true },
        );
    }

    // Draw separator below title
    const style = IconStyle.detect();
    const sep_char: u21 = switch (style) {
        .nerd_font => 0x2500, // '─' - Box-drawing character
        .ascii => '-',
    };
    var sep_col: u16 = 0;
    while (sep_col < tree_width) : (sep_col += 1) {
        rend.output.setCell(1, sep_col, .{
            .char = sep_char,
            .fg = theme.ui.tree_border,
            .bg = theme.ui.tree_bg,
            .attrs = .{},
        });
    }

    // Render tree nodes
    const start_row: u16 = 2; // After title and separator
    const viewport_height = visible_height - start_row;

    // Adjust scroll
    editor.file_tree.adjustScroll(viewport_height);

    const flat_view = editor.file_tree.flat_view.items;
    const scroll_offset = editor.file_tree.scroll_offset;
    const visible_count = @min(flat_view.len - scroll_offset, viewport_height);

    var i: usize = 0;
    while (i < visible_count) : (i += 1) {
        const node_idx = scroll_offset + i;
        if (node_idx >= flat_view.len) break;

        const node = flat_view[node_idx];
        const is_selected = node_idx == editor.file_tree.selected_index;
        const node_row = start_row + @as(u16, @intCast(i));

        // Render node
        try renderNode(rend, node, node_row, tree_width, is_selected, theme);
    }

    // Show scrollbar indicator if needed
    if (flat_view.len > viewport_height) {
        const total = flat_view.len;
        const scroll_percent = if (total > 0) (scroll_offset * 100) / total else 0;

        var scrollbar_buf: [16]u8 = undefined;
        const scrollbar_text = std.fmt.bufPrint(&scrollbar_buf, " {d}% ", .{scroll_percent}) catch " ";

        const scroll_row = visible_height - 1;
        const scroll_col = tree_width -| @as(u16, @intCast(scrollbar_text.len));

        rend.writeText(
            scroll_row,
            scroll_col,
            scrollbar_text,
            theme.ui.tree_scrollbar,
            theme.ui.tree_bg,
            .{ .dim = true },
        );
    }
}

/// Render a single tree node
fn renderNode(
    rend: *renderer.Renderer,
    node: *const TreeNode,
    row: u16,
    width: u16,
    is_selected: bool,
    theme: anytype,
) !void {
    // Calculate indent
    const indent = node.depth * 2;
    var col: u16 = @intCast(indent);

    // Highlight selected row
    if (is_selected) {
        var c: u16 = 0;
        while (c < width) : (c += 1) {
            rend.output.setCell(row, c, .{
                .char = ' ',
                .fg = theme.ui.tree_selected_fg,
                .bg = theme.ui.tree_selected_bg,
                .attrs = .{},
            });
        }
    }

    const fg = if (is_selected) theme.ui.tree_selected_fg else theme.ui.tree_fg;
    const bg = if (is_selected) theme.ui.tree_selected_bg else theme.ui.tree_bg;

    // Draw expand/collapse icon for directories
    if (node.is_dir) {
        const style = IconStyle.detect();
        const icon = switch (style) {
            .nerd_font => if (node.is_expanded) " " else " ", // Nerd Font chevrons
            .ascii => if (node.is_expanded) "- " else "+ ",
        };
        rend.writeText(row, col, icon, fg, bg, .{});
        col += @intCast(icon.len);
    } else {
        // Space for non-directories to align with files
        rend.writeText(row, col, "  ", fg, bg, .{});
        col += 2;
    }

    // Draw file/folder icon
    const file_icon = getIcon(node);
    rend.writeText(row, col, file_icon, getIconColor(node, theme), bg, .{});
    col += @intCast(file_icon.len);

    // Space after icon
    rend.writeText(row, col, " ", fg, bg, .{});
    col += 1;

    // Draw name (truncate if needed)
    const max_name_len = width -| col -| 1;
    const name = if (node.name.len > max_name_len)
        node.name[0..max_name_len]
    else
        node.name;

    rend.writeText(
        row,
        col,
        name,
        if (node.is_dir) theme.ui.tree_dir_fg else theme.ui.tree_file_fg,
        bg,
        if (is_selected) .{ .bold = true } else .{},
    );
}

/// Icon style configuration
const IconStyle = enum {
    nerd_font, // Nerd Font icons (most terminals with patched fonts)
    ascii, // Pure ASCII fallback

    /// Detect best icon style based on environment
    fn detect() IconStyle {
        // Check for Nerd Font indicator environment variable
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "NERD_FONT") catch null) |val| {
            std.heap.page_allocator.free(val);
            return .nerd_font;
        }

        // Check TERM for known compatible terminals
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "TERM_PROGRAM") catch null) |term_program| {
            defer std.heap.page_allocator.free(term_program);
            // iTerm2, Warp, Kitty, Alacritty typically have Nerd Fonts
            if (std.mem.indexOf(u8, term_program, "iTerm") != null or
                std.mem.indexOf(u8, term_program, "WezTerm") != null or
                std.mem.indexOf(u8, term_program, "kitty") != null or
                std.mem.indexOf(u8, term_program, "Alacritty") != null)
            {
                return .nerd_font;
            }
        }

        // Default to ASCII for safety
        return .ascii;
    }
};

/// Get icon for file/directory with style detection
fn getIcon(node: *const TreeNode) []const u8 {
    const style = IconStyle.detect();

    if (node.is_dir) {
        return switch (style) {
            .nerd_font => "", // Nerd Font folder icon
            .ascii => "/",
        };
    }

    const ext = std.fs.path.extension(node.name);

    return switch (style) {
        .nerd_font => blk: {
            // Nerd Font file type icons
            if (std.mem.eql(u8, ext, ".zig")) break :blk ""; // Lightning bolt
            if (std.mem.eql(u8, ext, ".js")) break :blk "";
            if (std.mem.eql(u8, ext, ".ts")) break :blk "";
            if (std.mem.eql(u8, ext, ".json")) break :blk "";
            if (std.mem.eql(u8, ext, ".md")) break :blk "";
            if (std.mem.eql(u8, ext, ".txt")) break :blk "";
            if (std.mem.eql(u8, ext, ".toml")) break :blk "";
            if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) break :blk "";
            if (std.mem.eql(u8, ext, ".rs")) break :blk "";
            if (std.mem.eql(u8, ext, ".go")) break :blk "";
            if (std.mem.eql(u8, ext, ".py")) break :blk "";
            if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) break :blk "";
            if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".hpp")) break :blk "";
            if (std.mem.eql(u8, ext, ".sh")) break :blk "";
            if (std.mem.eql(u8, ext, ".lua")) break :blk "";
            if (std.mem.eql(u8, ext, ".vim")) break :blk "";
            if (std.mem.eql(u8, ext, ".git")) break :blk "";
            if (std.mem.eql(u8, ext, ".gitignore")) break :blk "";
            break :blk ""; // Generic file
        },
        .ascii => blk: {
            // ASCII fallback
            if (std.mem.eql(u8, ext, ".zig")) break :blk "Z";
            if (std.mem.eql(u8, ext, ".js")) break :blk "J";
            if (std.mem.eql(u8, ext, ".ts")) break :blk "T";
            if (std.mem.eql(u8, ext, ".json")) break :blk "{}";
            if (std.mem.eql(u8, ext, ".md")) break :blk "M";
            if (std.mem.eql(u8, ext, ".txt")) break :blk "t";
            if (std.mem.eql(u8, ext, ".toml") or
                std.mem.eql(u8, ext, ".yaml") or
                std.mem.eql(u8, ext, ".yml")) break :blk "c";
            if (std.mem.eql(u8, ext, ".rs")) break :blk "R";
            if (std.mem.eql(u8, ext, ".go")) break :blk "G";
            if (std.mem.eql(u8, ext, ".py")) break :blk "P";
            if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) break :blk "C";
            if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".hpp")) break :blk "C+";
            if (std.mem.eql(u8, ext, ".sh")) break :blk "sh";
            break :blk "·";
        },
    };
}

/// Get color for icon
fn getIconColor(node: *const TreeNode, theme: anytype) Color {
    if (node.is_dir) return theme.palette.accent_purple;

    const ext = std.fs.path.extension(node.name);

    if (std.mem.eql(u8, ext, ".zig")) return theme.palette.accent_cyan;
    if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".ts")) return theme.palette.accent_yellow;
    if (std.mem.eql(u8, ext, ".json")) return theme.palette.accent_teal;
    if (std.mem.eql(u8, ext, ".md")) return theme.palette.accent_blue;
    if (std.mem.eql(u8, ext, ".rs")) return theme.palette.accent_orange;
    if (std.mem.eql(u8, ext, ".go")) return theme.palette.accent_cyan;
    if (std.mem.eql(u8, ext, ".py")) return theme.palette.accent_blue;

    return theme.ui.tree_file_fg;
}
