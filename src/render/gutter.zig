//! Gutter rendering - line numbers, git status, diagnostics

const std = @import("std");
const renderer = @import("renderer.zig");
const Color = renderer.Color;
const Attrs = renderer.Attrs;
const diagnostics_render = @import("diagnostics.zig");
const LspDiagnostics = @import("../lsp/diagnostics.zig");
const Theme = @import("../editor/theme.zig").Theme;

/// Gutter configuration
pub const GutterConfig = struct {
    show_line_numbers: bool = true,
    line_number_style: LineNumberStyle = .relative,
    show_git_status: bool = false, // Git integration pending
    show_diagnostics: bool = true, // LSP diagnostic indicators enabled
    width: u16 = 5, // Width of gutter in characters

    pub const LineNumberStyle = enum {
        absolute, // 1, 2, 3, 4, ...
        relative, // Show distance from cursor
    };
};

/// Render gutter for given line range
pub fn render(
    rend: *renderer.Renderer,
    config: GutterConfig,
    start_line: usize,
    end_line: usize,
    cursor_line: usize,
    theme: *const Theme,
) !void {
    try renderWithDiagnostics(rend, config, start_line, end_line, cursor_line, null, null, theme);
}

/// Render gutter with diagnostic support
pub fn renderWithDiagnostics(
    rend: *renderer.Renderer,
    config: GutterConfig,
    start_line: usize,
    end_line: usize,
    cursor_line: usize,
    diagnostic_manager: ?*const LspDiagnostics.DiagnosticManager,
    file_uri: ?[]const u8,
    theme: *const Theme,
) !void {
    if (!config.show_line_numbers) return;

    var row: u16 = 0;
    var line = start_line;

    while (line < end_line) : ({
        line += 1;
        row += 1;
    }) {
        const line_num = switch (config.line_number_style) {
            .absolute => line + 1, // 1-indexed
            .relative => blk: {
                if (line == cursor_line) {
                    break :blk line + 1; // Show absolute on cursor line
                }
                const dist = if (line > cursor_line)
                    line - cursor_line
                else
                    cursor_line - line;
                break :blk dist;
            },
        };

        // Format line number
        var buf: [16]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{d:>4} ", .{line_num}) catch "     ";

        // Color: cursor line is highlighted
        const fg_color: Color = if (line == cursor_line)
            theme.ui.gutter_line_number_active
        else
            theme.ui.gutter_line_number;

        rend.writeText(
            row,
            0,
            text,
            fg_color,
            .default,
            if (line == cursor_line) .{ .bold = true } else .{},
        );

        // Render diagnostic icon if present
        if (config.show_diagnostics) {
            if (diagnostic_manager) |manager| {
                if (file_uri) |uri| {
                    const severity = diagnostics_render.getSeverestDiagnosticForLine(
                        manager,
                        uri,
                        @intCast(line),
                    );

                    if (severity) |sev| {
                        const icons = diagnostics_render.DiagnosticIcons{};
                        // Render icon after line number (col 4 is usually safe)
                        diagnostics_render.renderGutterIcon(
                            rend,
                            row,
                            4, // Position after line number
                            sev,
                            icons,
                            theme,
                        );
                    }
                }
            }
        }
    }
}

/// Calculate gutter width based on configuration
pub fn calculateWidth(config: GutterConfig, total_lines: usize) u16 {
    _ = total_lines; // Unused - format string determines width
    if (!config.show_line_numbers) return 0;

    // FIXED: Return the actual width used by the format string "{d:>4} " (5 characters)
    // Previous bug: calculated dynamic width (e.g., 2 for <10 lines) but format always used 5 chars
    // This caused text to start at column 2 while gutter occupied columns 0-4,
    // resulting in 3 characters being overwritten by line numbers
    return 5; // 4 digits + 1 space, matching the format string
}
