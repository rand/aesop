//! File finder rendering
//! Displays filtered file list as an overlay

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;

const Editor = @import("../editor/editor.zig").Editor;
const FileFinder = @import("../editor/file_finder.zig");

/// Render file finder overlay (centered popup)
pub fn render(rend: *renderer.Renderer, editor: *Editor, allocator: std.mem.Allocator) !void {
    if (!editor.file_finder.visible) return;

    const size = rend.getSize();

    // Get filtered files
    const matches = try editor.file_finder.filterFiles(allocator);
    defer allocator.free(matches);

    // Calculate finder dimensions
    const finder_height: u16 = @min(@as(u16, @intCast(matches.len + 3)), size.height -| 4); // +3 for border and query
    const finder_width: u16 = @min(70, size.width -| 4); // Wider for file paths

    // Center the finder
    const start_row = (size.height -| finder_height) / 2;
    const start_col = (size.width -| finder_width) / 2;

    // Draw background box
    var row: u16 = 0;
    while (row < finder_height) : (row += 1) {
        var col: u16 = 0;
        while (col < finder_width) : (col += 1) {
            rend.output.setCell(start_row + row, start_col + col, .{
                .char = ' ',
                .fg = .{ .standard = .white },
                .bg = .{ .standard = .black },
                .attrs = .{},
            });
        }
    }

    // Draw border
    drawBorder(rend, start_row, start_col, finder_width, finder_height);

    // Draw title
    const title = " Find Files ";
    const title_col = start_col + (finder_width -| @as(u16, @intCast(title.len))) / 2;
    rend.writeText(start_row, title_col, title, .{ .standard = .green }, .{ .standard = .black }, .{ .bold = true }, null);

    // Draw query line
    var query_buf: [128]u8 = undefined;
    const query_text = std.fmt.bufPrint(
        &query_buf,
        " > {s}",
        .{editor.file_finder.getQuery()},
    ) catch " > ";

    rend.writeText(start_row + 1, start_col + 1, query_text, .{ .standard = .yellow }, .{ .standard = .black }, .{}, null);

    // Draw separator
    var sep_col: u16 = 1;
    while (sep_col < finder_width - 1) : (sep_col += 1) {
        rend.output.setCell(start_row + 2, start_col + sep_col, .{
            .char = '─',
            .fg = .{ .standard = .white },
            .bg = .{ .standard = .black },
            .attrs = .{},
        });
    }

    // Draw file list
    const max_items: u16 = finder_height -| 4; // Subtract border, query, separator
    const visible_matches = @min(matches.len, max_items);

    var i: usize = 0;
    while (i < visible_matches) : (i += 1) {
        const match = matches[i];
        const is_selected = i == editor.file_finder.selected_index;

        const item_row = start_row + 3 + @as(u16, @intCast(i));

        // Highlight selected item
        if (is_selected) {
            var col: u16 = 1;
            while (col < finder_width - 1) : (col += 1) {
                rend.output.setCell(item_row, start_col + col, .{
                    .char = ' ',
                    .fg = .{ .standard = .black },
                    .bg = .{ .standard = .green },
                    .attrs = .{},
                });
            }
        }

        // Format file entry with icon
        var item_buf: [256]u8 = undefined;
        const icon = getFileIcon(match.path);
        const item_text = std.fmt.bufPrint(
            &item_buf,
            " {s} {s}",
            .{ icon, match.path },
        ) catch "";

        const fg = if (is_selected) Color{ .standard = .black } else Color{ .standard = .white };
        const bg = if (is_selected) Color{ .standard = .green } else Color{ .standard = .black };

        rend.writeText(item_row, start_col + 1, item_text[0..@min(item_text.len, finder_width - 2)], fg, bg, if (is_selected) .{ .bold = true } else .{}, null);
    }

    // Show count
    if (matches.len > 0) {
        var count_buf: [32]u8 = undefined;
        const count_text = std.fmt.bufPrint(
            &count_buf,
            " {d}/{d} ",
            .{ editor.file_finder.selected_index + 1, matches.len },
        ) catch "";

        const count_col = start_col + finder_width -| @as(u16, @intCast(count_text.len)) - 1;
        rend.writeText(start_row + finder_height - 1, count_col, count_text, .{ .standard = .green }, .{ .standard = .black }, .{}, null);
    } else if (editor.file_finder.getQuery().len > 0) {
        // Show "no matches" message
        const no_match = " No matches ";
        const no_match_col = start_col + (finder_width -| @as(u16, @intCast(no_match.len))) / 2;
        rend.writeText(start_row + 3, no_match_col, no_match, .{ .standard = .bright_black }, .{ .standard = .black }, .{}, null);
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

/// Get file icon based on extension
fn getFileIcon(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);

    if (std.mem.eql(u8, ext, ".zig")) return "⚡";
    if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".ts")) return "📜";
    if (std.mem.eql(u8, ext, ".json")) return "{}";
    if (std.mem.eql(u8, ext, ".md")) return "📝";
    if (std.mem.eql(u8, ext, ".txt")) return "📄";
    if (std.mem.eql(u8, ext, ".toml") or std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return "⚙";
    if (std.mem.eql(u8, ext, ".rs")) return "🦀";
    if (std.mem.eql(u8, ext, ".go")) return "🐹";
    if (std.mem.eql(u8, ext, ".py")) return "🐍";
    if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h") or std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".hpp")) return "C";

    return "📄";
}
