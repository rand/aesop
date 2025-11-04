//! Yonce Dark Theme
//! A bold, vibrant dark theme with electric accents
//! Inspired by https://yoncetheme.com/

const Theme = @import("../theme.zig").Theme;
const ColorPalette = @import("../theme.zig").ColorPalette;
const UIColors = @import("../theme.zig").UIColors;
const SyntaxColors = @import("../theme.zig").SyntaxColors;
const Color = @import("../../render/buffer.zig").Color;

/// Yonce Dark theme - vibrant and electric
pub const yonce_dark = Theme{
    .name = "Yonce Dark",
    .palette = ColorPalette{
        // Base colors
        .background = Color{ .rgb = .{ .r = 0x12, .g = 0x12, .b = 0x12 } }, // #121212
        .background_lighter = Color{ .rgb = .{ .r = 0x2F, .g = 0x2F, .b = 0x2F } }, // #2F2F2F
        .foreground = Color{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }, // #FFFFFF
        .foreground_dim = Color{ .rgb = .{ .r = 0x80, .g = 0x80, .b = 0x80 } }, // #808080

        // Accent colors (Yonce signature colors)
        .accent_pink = Color{ .rgb = .{ .r = 0xFC, .g = 0x43, .b = 0x84 } }, // #FC4384
        .accent_teal = Color{ .rgb = .{ .r = 0x00, .g = 0xA7, .b = 0xAA } }, // #00A7AA
        .accent_cyan = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // #37E5E7
        .accent_purple = Color{ .rgb = .{ .r = 0xA0, .g = 0x6F, .b = 0xCA } }, // #A06FCA

        // Semantic colors
        .success = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // Cyan
        .warning = Color{ .rgb = .{ .r = 0xFC, .g = 0x43, .b = 0x84 } }, // Pink (bold choice!)
        .error = Color{ .rgb = .{ .r = 0xFF, .g = 0x44, .b = 0x44 } }, // Bright red
        .info = Color{ .rgb = .{ .r = 0xA0, .g = 0x6F, .b = 0xCA } }, // Purple
    },

    .ui = UIColors{
        // Gutter
        .gutter_line_number = Color{ .rgb = .{ .r = 0x60, .g = 0x60, .b = 0x60 } }, // Dim gray
        .gutter_line_number_active = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // Cyan

        // Editor highlights
        .cursor_line_bg = Color{ .rgb = .{ .r = 0x1E, .g = 0x1E, .b = 0x1E } }, // Subtle highlight
        .selection_bg = Color{ .rgb = .{ .r = 0x50, .g = 0x35, .b = 0x64 } }, // Purple tint
        .search_match_bg = Color{ .rgb = .{ .r = 0x7E, .g = 0x20, .b = 0x42 } }, // Pink tint

        // Status line
        .statusline_bg = Color{ .rgb = .{ .r = 0x2F, .g = 0x2F, .b = 0x2F } }, // Charcoal
        .statusline_fg = Color{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }, // White

        // Status line mode badges
        .statusline_mode_normal_bg = Color{ .rgb = .{ .r = 0x00, .g = 0xA7, .b = 0xAA } }, // Teal
        .statusline_mode_normal_fg = Color{ .rgb = .{ .r = 0x00, .g = 0x00, .b = 0x00 } }, // Black
        .statusline_mode_insert_bg = Color{ .rgb = .{ .r = 0xFC, .g = 0x43, .b = 0x84 } }, // Pink
        .statusline_mode_insert_fg = Color{ .rgb = .{ .r = 0x00, .g = 0x00, .b = 0x00 } }, // Black
        .statusline_mode_select_bg = Color{ .rgb = .{ .r = 0xA0, .g = 0x6F, .b = 0xCA } }, // Purple
        .statusline_mode_select_fg = Color{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }, // White
        .statusline_mode_command_bg = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // Cyan
        .statusline_mode_command_fg = Color{ .rgb = .{ .r = 0x00, .g = 0x00, .b = 0x00 } }, // Black

        // Context bar
        .contextbar_bg = Color{ .rgb = .{ .r = 0x1E, .g = 0x1E, .b = 0x28 } }, // Dark gray-blue
        .contextbar_fg = Color{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }, // White
        .contextbar_hint_key = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // Cyan
        .contextbar_separator = Color{ .rgb = .{ .r = 0x64, .g = 0x64, .b = 0x64 } }, // Dim gray
        .contextbar_welcome = Color{ .rgb = .{ .r = 0x00, .g = 0xA7, .b = 0xAA } }, // Teal

        // Overlays (palette, file finder, buffer switcher)
        .popup_bg = Color{ .rgb = .{ .r = 0x25, .g = 0x25, .b = 0x25 } }, // Mid-tone gray
        .popup_fg = Color{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }, // White
        .popup_border = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // Cyan
        .popup_selected_bg = Color{ .rgb = .{ .r = 0x3A, .g = 0x3A, .b = 0x3A } }, // Light gray
        .popup_selected_fg = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // Cyan

        // Messages
        .message_info_fg = Color{ .rgb = .{ .r = 0xA0, .g = 0x6F, .b = 0xCA } }, // Purple
        .message_info_bg = Color{ .rgb = .{ .r = 0x2F, .g = 0x2F, .b = 0x2F } }, // Charcoal
        .message_warning_fg = Color{ .rgb = .{ .r = 0xFC, .g = 0x43, .b = 0x84 } }, // Pink
        .message_warning_bg = Color{ .rgb = .{ .r = 0x2F, .g = 0x2F, .b = 0x2F } }, // Charcoal
        .message_error_fg = Color{ .rgb = .{ .r = 0xFF, .g = 0x44, .b = 0x44 } }, // Red
        .message_error_bg = Color{ .rgb = .{ .r = 0x2F, .g = 0x2F, .b = 0x2F } }, // Charcoal

        // Diagnostics
        .diagnostic_error = Color{ .rgb = .{ .r = 0xFF, .g = 0x44, .b = 0x44 } }, // Red
        .diagnostic_warning = Color{ .rgb = .{ .r = 0xFC, .g = 0x43, .b = 0x84 } }, // Pink
        .diagnostic_info = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // Cyan
        .diagnostic_hint = Color{ .rgb = .{ .r = 0x80, .g = 0x80, .b = 0x80 } }, // Gray
    },

    .syntax = SyntaxColors{
        // Keywords - Bold pink for maximum attention
        .keyword = Color{ .rgb = .{ .r = 0xFC, .g = 0x43, .b = 0x84 } }, // #FC4384 (pink)

        // Functions - Electric cyan, stands out
        .function_name = Color{ .rgb = .{ .r = 0x37, .g = 0xE5, .b = 0xE7 } }, // #37E5E7 (cyan)

        // Types - Muted teal, distinct but not overwhelming
        .type_name = Color{ .rgb = .{ .r = 0x00, .g = 0xA7, .b = 0xAA } }, // #00A7AA (teal)

        // Strings - Classic green for readability
        .string = Color{ .rgb = .{ .r = 0x4E, .g = 0xC9, .b = 0xB0 } }, // #4EC9B0 (green)

        // Numbers - Warm orange for contrast
        .number = Color{ .rgb = .{ .r = 0xCE, .g = 0x91, .b = 0x78 } }, // #CE9178 (orange)

        // Comments - Dim green, recedes to background
        .comment = Color{ .rgb = .{ .r = 0x6A, .g = 0x99, .b = 0x55 } }, // #6A9955 (dim green)

        // Constants - Soft purple, distinctive
        .constant = Color{ .rgb = .{ .r = 0xA0, .g = 0x6F, .b = 0xCA } }, // #A06FCA (purple)

        // Variables - Light gray, readable default
        .variable = Color{ .rgb = .{ .r = 0xD4, .g = 0xD4, .b = 0xD4 } }, // #D4D4D4 (light gray)

        // Operators - White, neutral
        .operator = Color{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }, // #FFFFFF (white)

        // Punctuation - White, neutral
        .punctuation = Color{ .rgb = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } }, // #FFFFFF (white)

        // Parse errors - Bright red
        .error_node = Color{ .rgb = .{ .r = 0xFF, .g = 0x44, .b = 0x44 } }, // #FF4444 (red)
    },
};
