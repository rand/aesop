//! Tree-sitter integration for syntax highlighting
//! Provides incremental parsing and syntax tree queries

const std = @import("std");
const Buffer = @import("../buffer/manager.zig").Buffer;
const Highlight = @import("highlight.zig");

/// Syntax node type - represents a parsed syntax element
pub const SyntaxNode = struct {
    start_byte: usize,
    end_byte: usize,
    start_line: usize,
    end_line: usize,
    node_type: []const u8, // e.g., "function", "string", "comment"

    pub fn contains(self: SyntaxNode, byte_offset: usize) bool {
        return byte_offset >= self.start_byte and byte_offset < self.end_byte;
    }

    pub fn containsLine(self: SyntaxNode, line: usize) bool {
        return line >= self.start_line and line <= self.end_line;
    }
};

/// Highlight group - maps to terminal colors/styles
pub const HighlightGroup = enum {
    keyword, // if, for, return, etc.
    function_name, // Function identifiers
    type_name, // Type/struct names
    variable, // Variable names
    constant, // Constants/enums
    string, // String literals
    number, // Numeric literals
    comment, // Comments
    operator, // +, -, *, etc.
    punctuation, // Delimiters
    error_node, // Parse errors

    /// Convert to renderer color (uses standard 16-color palette)
    pub fn toColor(self: HighlightGroup) @import("../render/buffer.zig").Color {
        const Color = @import("../render/buffer.zig").Color;

        return switch (self) {
            .keyword => Color.magenta,
            .function_name => Color.yellow,
            .type_name => Color.cyan,
            .variable => Color.white,
            .constant => Color.bright_magenta,
            .string => Color.green,
            .number => Color.bright_yellow,
            .comment => Color.bright_black, // Gray
            .operator => Color.white,
            .punctuation => Color.white,
            .error_node => Color.red,
        };
    }

    /// Legacy ANSI code method (for reference)
    pub fn toAnsiCode(self: HighlightGroup) []const u8 {
        return switch (self) {
            .keyword => "\x1b[35m", // Magenta
            .function_name => "\x1b[33m", // Yellow
            .type_name => "\x1b[36m", // Cyan
            .variable => "\x1b[37m", // White
            .constant => "\x1b[95m", // Bright Magenta
            .string => "\x1b[32m", // Green
            .number => "\x1b[93m", // Bright Yellow
            .comment => "\x1b[90m", // Bright black (gray)
            .operator => "\x1b[37m", // White
            .punctuation => "\x1b[37m", // White
            .error_node => "\x1b[31m", // Red
        };
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

/// Parser state - manages syntax tree for a buffer
pub const Parser = struct {
    language: Language,
    allocator: std.mem.Allocator,
    // Tree-sitter state would go here
    // For now, this is a placeholder for the actual tree-sitter integration

    pub fn init(allocator: std.mem.Allocator, language: Language) !Parser {
        return .{
            .language = language,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Parser) void {
        _ = self;
    }

    /// Parse buffer and return syntax tree
    pub fn parse(self: *Parser, text: []const u8) !void {
        _ = self;
        _ = text;
        // TODO: Call tree-sitter parser
        // For now, this is a no-op
    }

    /// Get highlights for a line range
    pub fn getHighlights(
        self: *Parser,
        text: []const u8,
        start_line: usize,
        end_line: usize,
    ) ![]HighlightToken {
        _ = start_line;
        _ = end_line;

        // Temporary: Basic keyword-based highlighting
        return try basicHighlight(self.allocator, text, self.language);
    }
};

/// Basic regex-free keyword highlighting (temporary until tree-sitter is integrated)
/// Uses the enhanced tokenizer from highlight.zig
fn basicHighlight(allocator: std.mem.Allocator, text: []const u8, language: Language) ![]HighlightToken {
    var tokens = std.ArrayList(HighlightToken).empty;
    errdefer tokens.deinit(allocator);

    // Convert Language to Highlight.Language
    const highlight_lang = switch (language) {
        .zig => Highlight.Language.zig,
        else => Highlight.Language.unknown,
    };

    // Process text line by line
    var line_num: usize = 0;
    var line_start: usize = 0;
    var i: usize = 0;

    while (i <= text.len) {
        // Find line boundaries
        const is_newline = (i < text.len and text[i] == '\n');
        const is_end = (i == text.len);

        if (is_newline or is_end) {
            const line_text = text[line_start..i];

            // Tokenize this line
            const line_tokens = Highlight.tokenizeLine(allocator, line_text, highlight_lang) catch |err| {
                // On error, skip this line
                std.debug.print("Warning: Failed to tokenize line {d}: {}\n", .{ line_num, err });
                if (is_newline) {
                    line_start = i + 1;
                    line_num += 1;
                }
                i += 1;
                continue;
            };
            defer allocator.free(line_tokens);

            // Convert line tokens to HighlightTokens
            for (line_tokens) |token| {
                const group = tokenTypeToHighlightGroup(token.type);

                try tokens.append(allocator, HighlightToken{
                    .start_byte = line_start + token.start,
                    .end_byte = line_start + token.end,
                    .line = line_num,
                    .group = group,
                });
            }

            if (is_newline) {
                line_start = i + 1;
                line_num += 1;
            }
        }

        i += 1;
    }

    return tokens.toOwnedSlice(allocator);
}

/// Map Highlight.TokenType to TreeSitter.HighlightGroup
fn tokenTypeToHighlightGroup(token_type: Highlight.TokenType) HighlightGroup {
    return switch (token_type) {
        .keyword => .keyword,
        .type_name => .type_name,
        .function_name => .function_name,
        .string => .string,
        .number => .number,
        .comment => .comment,
        .operator => .operator,
        .punctuation => .punctuation,
        .normal => .variable, // Default to variable color for normal text
    };
}

// === Tests ===

test "treesitter: language from filename" {
    try std.testing.expectEqual(Language.zig, Language.fromFilename("main.zig"));
    try std.testing.expectEqual(Language.rust, Language.fromFilename("main.rs"));
    try std.testing.expectEqual(Language.c, Language.fromFilename("main.c"));
    try std.testing.expectEqual(Language.plain_text, Language.fromFilename("README.txt"));
}

test "treesitter: parser init" {
    const allocator = std.testing.allocator;
    var parser = try Parser.init(allocator, .zig);
    defer parser.deinit();

    try std.testing.expectEqual(Language.zig, parser.language);
}

test "treesitter: basic keyword highlight" {
    const allocator = std.testing.allocator;
    const text = "const x = 5;\nfn main() {}\n";

    const tokens = try basicHighlight(allocator, text, .zig);
    defer allocator.free(tokens);

    // Should highlight "const" and "fn"
    var found_const = false;
    var found_fn = false;

    for (tokens) |token| {
        if (token.group == .keyword) {
            const word = text[token.start_byte..token.end_byte];
            if (std.mem.eql(u8, word, "const")) found_const = true;
            if (std.mem.eql(u8, word, "fn")) found_fn = true;
        }
    }

    try std.testing.expect(found_const);
    try std.testing.expect(found_fn);
}

test "treesitter: string highlight" {
    const allocator = std.testing.allocator;
    const text = "const msg = \"hello\";\n";

    const tokens = try basicHighlight(allocator, text, .zig);
    defer allocator.free(tokens);

    var found_string = false;
    for (tokens) |token| {
        if (token.group == .string) {
            found_string = true;
            break;
        }
    }

    try std.testing.expect(found_string);
}

test "treesitter: comment highlight" {
    const allocator = std.testing.allocator;
    const text = "const x = 5; // comment\n";

    const tokens = try basicHighlight(allocator, text, .zig);
    defer allocator.free(tokens);

    var found_comment = false;
    for (tokens) |token| {
        if (token.group == .comment) {
            found_comment = true;
            break;
        }
    }

    try std.testing.expect(found_comment);
}
