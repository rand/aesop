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
pub fn render(rend: *renderer.Renderer, editor: *Editor, visible_height: usize, allocator: std.mem.Allocator) !void {
    _ = allocator;
    if (!editor.file_tree.visible) return;

    const theme = editor.getTheme();
    const size = rend.getSize();
    const tree_width = editor.file_tree.width;

    // Don't render if tree is wider than screen
    if (tree_width >= size.width) return;

    // Use provided visible height (already calculated to exclude status bars)

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

        // Draw vertical separator (Nerd Font box-drawing character)
        rend.output.setCell(row, tree_width, .{
            .char = 0x2502, // '│' - Box-drawing character
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
            null);
    }

    // Draw separator below title (Nerd Font box-drawing character)
    var sep_col: u16 = 0;
    while (sep_col < tree_width) : (sep_col += 1) {
        rend.output.setCell(1, sep_col, .{
            .char = 0x2500, // '─' - Box-drawing character
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

        const scroll_row: u16 = @intCast(visible_height - 1);
        const scroll_col = tree_width -| @as(u16, @intCast(scrollbar_text.len));

        rend.writeText(
            scroll_row,
            scroll_col,
            scrollbar_text,
            theme.ui.tree_scrollbar,
            theme.ui.tree_bg,
            .{ .dim = true },
            null);
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

    const fg = if (is_selected) theme.ui.tree_selected_fg else theme.ui.tree_fg;
    const bg = if (is_selected) theme.ui.tree_selected_bg else theme.ui.tree_bg;

    // ALWAYS fill the entire row background to prevent artifacts
    // This ensures any previous content is completely overwritten
    var c: u16 = 0;
    while (c < width) : (c += 1) {
        rend.output.setCell(row, c, .{
            .char = ' ',
            .fg = fg,
            .bg = bg,
            .attrs = .{},
        });
    }

    // Draw expand/collapse icon for directories (Nerd Font chevrons)
    if (node.is_dir) {
        const icon = if (node.is_expanded) " " else " "; // Chevron down/right
        rend.writeText(row, col, icon, fg, bg, .{}, null);
        col += @intCast(icon.len);
    } else {
        // Space for non-directories to align with files
        rend.writeText(row, col, "  ", fg, bg, .{}, null);
        col += 2;
    }

    // Draw file/folder icon
    const file_icon = getIcon(node);
    rend.writeText(row, col, file_icon, getIconColor(node, theme), bg, .{}, null);
    col += @intCast(file_icon.len);

    // Space after icon
    rend.writeText(row, col, " ", fg, bg, .{}, null);
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
        null);
}

/// Icon style configuration
/// NOTE: Nerd Fonts are now required for proper display
const IconStyle = enum {
    nerd_font, // Nerd Font icons (required)

    /// Always use Nerd Fonts (now required)
    fn detect() IconStyle {
        return .nerd_font;
    }
};

/// Get Nerd Font icon for file/directory
fn getIcon(node: *const TreeNode) []const u8 {
    if (node.is_dir) {
        return ""; // Nerd Font folder icon
    }

    const ext = std.fs.path.extension(node.name);

    // Nerd Font file type icons
    if (std.mem.eql(u8, ext, ".zig")) return ""; // Lightning bolt
    if (std.mem.eql(u8, ext, ".js")) return "";
    if (std.mem.eql(u8, ext, ".ts")) return "";
    if (std.mem.eql(u8, ext, ".json")) return "";
    if (std.mem.eql(u8, ext, ".md")) return "";
    if (std.mem.eql(u8, ext, ".txt")) return "";
    if (std.mem.eql(u8, ext, ".toml")) return "";
    if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return "";
    if (std.mem.eql(u8, ext, ".rs")) return "";
    if (std.mem.eql(u8, ext, ".go")) return "";
    if (std.mem.eql(u8, ext, ".py")) return "";
    if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return "";
    if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".hpp")) return "";
    if (std.mem.eql(u8, ext, ".sh")) return "";
    if (std.mem.eql(u8, ext, ".lua")) return "";
    if (std.mem.eql(u8, ext, ".vim")) return "";
    if (std.mem.eql(u8, ext, ".git")) return "";
    if (std.mem.eql(u8, ext, ".gitignore")) return "";

    return ""; // Generic file
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
