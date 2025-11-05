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

    // Fill title row background
    var col: u16 = 0;
    while (col < tree_width) : (col += 1) {
        rend.output.setCell(0, col, .{
            .char = ' ',
            .fg = theme.ui.tree_fg,
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
    // Only draw within tree area (0..tree_width-1)
    var sep_col: u16 = 0;
    while (sep_col < tree_width) : (sep_col += 1) {
        rend.output.setCell(1, sep_col, .{
            .char = 0x2500, // '─' - Box-drawing character
            .fg = theme.ui.tree_border,
            .bg = theme.ui.tree_bg,
            .attrs = .{},
        });
    }

    // Draw vertical separator for all rows at rightmost column of tree
    // tree_width is the separator column (e.g., for width 30, draws at column 30)
    // This is OUTSIDE the tree content area but before the buffer
    var row: u16 = 0;
    while (row < visible_height) : (row += 1) {
        if (tree_width < size.width) {
            rend.output.setCell(row, tree_width, .{
                .char = 0x2502, // '│' - Box-drawing character
                .fg = theme.ui.tree_border,
                .bg = theme.ui.tree_bg,
                .attrs = .{},
            });
        }
    }

    // Render tree nodes
    const start_row: u16 = 2; // After title and separator
    const viewport_height = visible_height - start_row;

    // Adjust scroll
    editor.file_tree.adjustScroll(viewport_height);

    const flat_view = editor.file_tree.flat_view.items;
    const scroll_offset = editor.file_tree.scroll_offset;

    // Prevent underflow: if scroll_offset >= flat_view.len, visible_count should be 0
    const visible_count = if (scroll_offset >= flat_view.len)
        0
    else
        @min(flat_view.len - scroll_offset, viewport_height);

    var i: usize = 0;
    while (i < visible_count) : (i += 1) {
        const node_idx = scroll_offset + i;
        if (node_idx >= flat_view.len) break;

        const node = flat_view[node_idx];

        // Safety check: ensure node and name are valid
        if (node.name.len == 0) {
            std.log.warn("Invalid node at index {}: empty name", .{node_idx});
            continue;
        }

        const is_selected = node_idx == editor.file_tree.selected_index;
        const node_row = start_row + @as(u16, @intCast(i));

        // Render node
        renderNode(rend, node, node_row, tree_width, is_selected, theme) catch |err| {
            std.log.warn("Failed to render node '{}': {}", .{std.zig.fmtEscapes(node.name), err});
            continue;
        };
    }

    // Fill empty rows below last node
    var empty_row = start_row + @as(u16, @intCast(visible_count));
    while (empty_row < visible_height) : (empty_row += 1) {
        var empty_col: u16 = 0;
        while (empty_col < tree_width) : (empty_col += 1) {
            rend.output.setCell(empty_row, empty_col, .{
                .char = ' ',
                .fg = theme.ui.tree_fg,
                .bg = theme.ui.tree_bg,
                .attrs = .{},
            });
        }
    }

    // NOTE: Scrollbar removed - caused visual clutter and positioning issues
    // Users can see scroll position from visible items and navigation still works
}

/// Smart truncation with ellipsis that preserves file extensions
fn truncateWithEllipsis(name: []const u8, max_len: u16, is_dir: bool) []const u8 {
    // If it fits, return as-is
    if (name.len <= max_len) return name;

    // Need to truncate - reserve space for ellipsis (3 bytes for '…')
    if (max_len < 4) {
        // Too small to show anything meaningful, just slice
        return if (max_len > 0) name[0..max_len] else "";
    }

    // For files, try to preserve extension
    if (!is_dir) {
        const ext = std.fs.path.extension(name);
        if (ext.len > 0 and ext.len < max_len - 4) {
            // Show start + "…" + extension (would need allocator for proper impl)
            // For now, just truncate from the end
            return name[0..max_len];
        }
    }

    // Default: truncate from end (leaving room for ellipsis would need allocator)
    // Just return truncated name without ellipsis for now (allocator needed for proper impl)
    return name[0..max_len];
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
    // Fill only up to width (not including the separator column)
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
        col += 2; // Space (1) + chevron icon (1 display char, 3 bytes)
    } else {
        // Space for non-directories to align with files
        rend.writeText(row, col, "  ", fg, bg, .{}, null);
        col += 2;
    }

    // Draw file/folder icon
    const file_icon = getIcon(node);
    rend.writeText(row, col, file_icon, getIconColor(node, theme), bg, .{}, null);
    col += 1; // Nerd Font icons display as 1 character (even though 3 bytes in UTF-8)

    // Space after icon
    rend.writeText(row, col, " ", fg, bg, .{}, null);
    col += 1;

    // Draw name (smart truncation with ellipsis if needed)
    // Ensure we have at least some space for the name
    // width is tree_width (e.g., 30), col is current position (e.g., 6-10)
    // We want: name ends before width, leaving at least 1 char of space
    const remaining_width = if (col >= width) 0 else width - col;
    const max_name_len = if (remaining_width > 1) remaining_width - 1 else 0;

    // Only draw if we have space
    if (max_name_len == 0) return;

    const name = truncateWithEllipsis(node.name, max_name_len, node.is_dir);

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
