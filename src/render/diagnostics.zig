//! Diagnostic gutter rendering
//! Renders error/warning icons in the gutter next to line numbers

const std = @import("std");
const Renderer = @import("renderer.zig").Renderer;
const Color = @import("buffer.zig").Color;
const LspDiagnostics = @import("../lsp/diagnostics.zig");
const DiagnosticSeverity = @import("../lsp/response_parser.zig").DiagnosticSeverity;

/// Diagnostic icon configuration
pub const DiagnosticIcons = struct {
    error_icon: []const u8 = "●", // Red circle for errors
    warning_icon: []const u8 = "▲", // Yellow triangle for warnings
    info_icon: []const u8 = "ⓘ", // Blue info circle
    hint_icon: []const u8 = "💡", // Light bulb for hints
};

/// Get color for diagnostic severity
pub fn getSeverityColor(severity: DiagnosticSeverity) Color {
    return switch (severity) {
        .@"error" => Color.red,
        .warning => Color.yellow,
        .information => Color.blue,
        .hint => Color.bright_black,
    };
}

/// Get icon for diagnostic severity
pub fn getSeverityIcon(severity: DiagnosticSeverity, icons: DiagnosticIcons) []const u8 {
    return switch (severity) {
        .@"error" => icons.error_icon,
        .warning => icons.warning_icon,
        .information => icons.info_icon,
        .hint => icons.hint_icon,
    };
}

/// Render diagnostic icon in gutter for a specific line
pub fn renderGutterIcon(
    rend: *Renderer,
    row: u16,
    col: u16,
    severity: DiagnosticSeverity,
    icons: DiagnosticIcons,
) void {
    const icon = getSeverityIcon(severity, icons);
    const color = getSeverityColor(severity);

    rend.writeText(row, col, icon, color, .default, .{});
}

/// Render diagnostic counts in statusline format
pub fn formatDiagnosticCounts(
    allocator: std.mem.Allocator,
    errors: usize,
    warnings: usize,
    info: usize,
    hints: usize,
) ![]const u8 {
    // Format: "2E 5W" (errors and warnings only, if present)
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);

    if (errors > 0) {
        const err_str = try std.fmt.allocPrint(allocator, "{d}E", .{errors});
        try parts.append(allocator, err_str);
    }

    if (warnings > 0) {
        const warn_str = try std.fmt.allocPrint(allocator, "{d}W", .{warnings});
        try parts.append(allocator, warn_str);
    }

    // Only show info and hints if no errors or warnings
    if (errors == 0 and warnings == 0) {
        if (info > 0) {
            const info_str = try std.fmt.allocPrint(allocator, "{d}I", .{info});
            try parts.append(allocator, info_str);
        }

        if (hints > 0) {
            const hint_str = try std.fmt.allocPrint(allocator, "{d}H", .{hints});
            try parts.append(allocator, hint_str);
        }
    }

    if (parts.items.len == 0) {
        return try allocator.dupe(u8, "");
    }

    // Join with spaces
    var result = std.ArrayList(u8).empty;
    defer result.deinit(allocator);

    for (parts.items, 0..) |part, i| {
        try result.appendSlice(allocator, part);
        allocator.free(part); // Free the individual part

        if (i < parts.items.len - 1) {
            try result.append(allocator, ' ');
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Helper to get the most severe diagnostic for a line from the diagnostic manager
pub fn getSeverestDiagnosticForLine(
    manager: *const LspDiagnostics.DiagnosticManager,
    uri: []const u8,
    line: u32,
) ?DiagnosticSeverity {
    const diagnostic = manager.getSeverestForLine(uri, line) orelse return null;
    return diagnostic.severity;
}

// === Tests ===

test "diagnostics: get severity color" {
    try std.testing.expectEqual(Color.red, getSeverityColor(.@"error"));
    try std.testing.expectEqual(Color.yellow, getSeverityColor(.warning));
    try std.testing.expectEqual(Color.blue, getSeverityColor(.information));
    try std.testing.expectEqual(Color.bright_black, getSeverityColor(.hint));
}

test "diagnostics: get severity icon" {
    const icons = DiagnosticIcons{};

    try std.testing.expectEqualStrings("●", getSeverityIcon(.@"error", icons));
    try std.testing.expectEqualStrings("▲", getSeverityIcon(.warning, icons));
    try std.testing.expectEqualStrings("ⓘ", getSeverityIcon(.information, icons));
    try std.testing.expectEqualStrings("💡", getSeverityIcon(.hint, icons));
}

test "diagnostics: format counts - errors and warnings" {
    const allocator = std.testing.allocator;

    const result = try formatDiagnosticCounts(allocator, 2, 5, 0, 0);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("2E 5W", result);
}

test "diagnostics: format counts - errors only" {
    const allocator = std.testing.allocator;

    const result = try formatDiagnosticCounts(allocator, 3, 0, 0, 0);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("3E", result);
}

test "diagnostics: format counts - empty" {
    const allocator = std.testing.allocator;

    const result = try formatDiagnosticCounts(allocator, 0, 0, 0, 0);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "diagnostics: format counts - info and hints when no errors" {
    const allocator = std.testing.allocator;

    const result = try formatDiagnosticCounts(allocator, 0, 0, 2, 3);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("2I 3H", result);
}
