//! No-op tree-sitter stub for when tree-sitter is disabled
//! Provides the same API as treesitter.zig but without any functionality

const std = @import("std");

/// Syntax node type - represents a parsed syntax element
pub const SyntaxNode = struct {
    start_byte: usize = 0,
    end_byte: usize = 0,
    start_line: usize = 0,
    end_line: usize = 0,
    node_type: []const u8 = "",

    pub fn contains(self: SyntaxNode, byte_offset: usize) bool {
        _ = self;
        _ = byte_offset;
        return false;
    }

    pub fn containsLine(self: SyntaxNode, line: usize) bool {
        _ = self;
        _ = line;
        return false;
    }
};

/// Highlight group - maps to terminal colors/styles
pub const HighlightGroup = enum {
    keyword,
    function_name,
    type_name,
    variable,
    constant,
    string,
    number,
    comment,
    operator,
    punctuation,
    error_node,

    pub fn toColor(self: HighlightGroup) @import("../render/buffer.zig").Color {
        _ = self;
        return @import("../render/buffer.zig").Color.white;
    }

    pub fn toAnsiCode(self: HighlightGroup) []const u8 {
        _ = self;
        return "\x1b[37m"; // White
    }
};

/// Token with highlighting information
pub const HighlightToken = struct {
    start_byte: usize,
    end_byte: usize,
    line: usize,
    group: HighlightGroup,
};

/// Language configuration
pub const Language = enum {
    zig,
    c,
    rust,
    go,
    python,
    javascript,
    typescript,
    json,
    markdown,
    plain_text,

    pub fn fromFilename(filename: []const u8) Language {
        if (std.mem.endsWith(u8, filename, ".zig")) return .zig;
        if (std.mem.endsWith(u8, filename, ".c") or std.mem.endsWith(u8, filename, ".h")) return .c;
        if (std.mem.endsWith(u8, filename, ".rs")) return .rust;
        if (std.mem.endsWith(u8, filename, ".go")) return .go;
        if (std.mem.endsWith(u8, filename, ".py")) return .python;
        if (std.mem.endsWith(u8, filename, ".js")) return .javascript;
        if (std.mem.endsWith(u8, filename, ".ts")) return .typescript;
        if (std.mem.endsWith(u8, filename, ".json")) return .json;
        if (std.mem.endsWith(u8, filename, ".md")) return .markdown;
        return .plain_text;
    }

    pub fn getName(self: Language) []const u8 {
        return switch (self) {
            .zig => "zig",
            .c => "c",
            .rust => "rust",
            .go => "go",
            .python => "python",
            .javascript => "javascript",
            .typescript => "typescript",
            .json => "json",
            .markdown => "markdown",
            .plain_text => "plain_text",
        };
    }
};

/// Stub parser that does nothing
pub const Parser = struct {
    allocator: std.mem.Allocator,
    language: Language,

    /// Initialize parser (no-op)
    pub fn init(allocator: std.mem.Allocator, language: Language) !Parser {
        return Parser{
            .allocator = allocator,
            .language = language,
        };
    }

    /// Clean up parser (no-op)
    pub fn deinit(self: *Parser) void {
        _ = self;
    }

    /// Parse buffer (no-op, returns empty highlights)
    pub fn parse(self: *Parser, text: []const u8) !void {
        _ = self;
        _ = text;
    }

    /// Get syntax highlights (returns empty array)
    pub fn getHighlights(self: *Parser, text: []const u8, start_line: usize, end_line: usize) ![]HighlightToken {
        _ = self;
        _ = text;
        _ = start_line;
        _ = end_line;
        // Return empty array - no syntax highlighting when tree-sitter is disabled
        return &[_]HighlightToken{};
    }

    /// Get syntax tree root (returns null)
    pub fn getRoot(self: *const Parser) ?SyntaxNode {
        _ = self;
        return null;
    }
};
