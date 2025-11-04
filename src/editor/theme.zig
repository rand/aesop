//! Theme system for editor styling
//! Provides centralized color management inspired by Helix editor

const std = @import("std");
const Color = @import("../render/buffer.zig").Color;

/// Complete theme definition
pub const Theme = struct {
    name: []const u8,
    palette: ColorPalette,
    ui: UIColors,
    syntax: SyntaxColors,

    /// Get color with alpha blending (for future use)
    pub fn withAlpha(color: Color, alpha: u8) Color {
        _ = alpha; // TODO: Implement alpha blending
        return color;
    }
};

/// Color palette - base colors for the theme
pub const ColorPalette = struct {
    // Base colors
    background: Color,
    background_lighter: Color,
    foreground: Color,
    foreground_dim: Color,

    // Accent colors
    accent_pink: Color,
    accent_teal: Color,
    accent_cyan: Color,
    accent_purple: Color,

    // Semantic colors
    success: Color,
    warning: Color,
    err: Color, // "error" is reserved keyword
    info: Color,
};

/// UI element colors
pub const UIColors = struct {
    // Gutter
    gutter_line_number: Color,
    gutter_line_number_active: Color,

    // Editor highlights
    cursor_line_bg: Color,
    selection_bg: Color,
    search_match_bg: Color,

    // Status line
    statusline_bg: Color,
    statusline_fg: Color,
    statusline_mode_normal_bg: Color,
    statusline_mode_normal_fg: Color,
    statusline_mode_insert_bg: Color,
    statusline_mode_insert_fg: Color,
    statusline_mode_select_bg: Color,
    statusline_mode_select_fg: Color,
    statusline_mode_command_bg: Color,
    statusline_mode_command_fg: Color,

    // Context bar
    contextbar_bg: Color,
    contextbar_fg: Color,
    contextbar_hint_key: Color,
    contextbar_separator: Color,
    contextbar_welcome: Color,

    // Overlays (palette, file finder, buffer switcher)
    popup_bg: Color,
    popup_fg: Color,
    popup_border: Color,
    popup_selected_bg: Color,
    popup_selected_fg: Color,

    // Messages
    message_info_fg: Color,
    message_info_bg: Color,
    message_warning_fg: Color,
    message_warning_bg: Color,
    message_error_fg: Color,
    message_error_bg: Color,

    // Diagnostics
    diagnostic_error: Color,
    diagnostic_warning: Color,
    diagnostic_info: Color,
    diagnostic_hint: Color,
};

/// Syntax highlighting colors
pub const SyntaxColors = struct {
    keyword: Color, // if, for, return, const
    function_name: Color, // Function definitions/calls
    type_name: Color, // Types, structs, classes
    variable: Color, // Variables
    constant: Color, // Constants, enums
    string: Color, // String literals
    number: Color, // Numeric literals
    comment: Color, // Comments
    operator: Color, // +, -, *, etc.
    punctuation: Color, // Delimiters
    error_node: Color, // Parse errors
};

/// Theme manager
pub const ThemeManager = struct {
    current_theme: *const Theme,
    allocator: std.mem.Allocator,

    /// Initialize with default theme
    pub fn init(allocator: std.mem.Allocator, theme: *const Theme) ThemeManager {
        return .{
            .current_theme = theme,
            .allocator = allocator,
        };
    }

    /// Get current theme
    pub fn getTheme(self: *const ThemeManager) *const Theme {
        return self.current_theme;
    }

    /// Switch to a different theme
    pub fn setTheme(self: *ThemeManager, theme: *const Theme) void {
        self.current_theme = theme;
    }
};
