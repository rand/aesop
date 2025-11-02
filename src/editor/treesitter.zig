//! Tree-sitter integration for syntax highlighting
//! Provides incremental parsing and syntax tree queries

const std = @import("std");
const Buffer = @import("../buffer/manager.zig").Buffer;

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
    keyword,       // if, for, return, etc.
    function_name, // Function identifiers
    type_name,     // Type/struct names
    variable,      // Variable names
    constant,      // Constants/enums
    string,        // String literals
    number,        // Numeric literals
    comment,       // Comments
    operator,      // +, -, *, etc.
    punctuation,   // Delimiters
    error_node,    // Parse errors

    pub fn toAnsiCode(self: HighlightGroup) []const u8 {
        return switch (self) {
            .keyword => "\x1b[35m",       // Magenta
            .function_name => "\x1b[33m", // Yellow
            .type_name => "\x1b[36m",     // Cyan
            .variable => "\x1b[37m",      // White
            .constant => "\x1b[35m",      // Magenta
            .string => "\x1b[32m",        // Green
            .number => "\x1b[33m",        // Yellow
            .comment => "\x1b[90m",       // Bright black (gray)
            .operator => "\x1b[37m",      // White
            .punctuation => "\x1b[37m",   // White
            .error_node => "\x1b[31m",    // Red
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
fn basicHighlight(allocator: std.mem.Allocator, text: []const u8, language: Language) ![]HighlightToken {
    var tokens = std.ArrayList(HighlightToken).empty;
    errdefer tokens.deinit(allocator);

    const keywords = getKeywords(language);

    var line: usize = 0;
    var byte_offset: usize = 0;
    var token_start: ?usize = null;
    var in_string = false;
    var in_comment = false;

    while (byte_offset < text.len) : (byte_offset += 1) {
        const c = text[byte_offset];

        // Track line numbers
        if (c == '\n') {
            line += 1;
            in_comment = false; // Single-line comment ends
            continue;
        }

        // String detection (basic)
        if (c == '"' and !in_comment) {
            if (!in_string) {
                token_start = byte_offset;
                in_string = true;
            } else {
                if (token_start) |start| {
                    try tokens.append(allocator, HighlightToken{
                        .start_byte = start,
                        .end_byte = byte_offset + 1,
                        .line = line,
                        .group = .string,
                    });
                }
                in_string = false;
                token_start = null;
            }
            continue;
        }

        // Comment detection (basic: //)
        if (!in_string and byte_offset + 1 < text.len and
            text[byte_offset] == '/' and text[byte_offset + 1] == '/') {
            in_comment = true;
            token_start = byte_offset;
            continue;
        }

        if (in_comment) continue;
        if (in_string) continue;

        // Keyword matching (simplified)
        if (isAlphanumeric(c) or c == '_') {
            if (token_start == null) {
                token_start = byte_offset;
            }
        } else {
            if (token_start) |start| {
                const word = text[start..byte_offset];
                if (isKeyword(word, keywords)) {
                    try tokens.append(allocator, HighlightToken{
                        .start_byte = start,
                        .end_byte = byte_offset,
                        .line = line,
                        .group = .keyword,
                    });
                }
                token_start = null;
            }
        }
    }

    // Handle comment at end of file
    if (in_comment) {
        if (token_start) |start| {
            try tokens.append(allocator, HighlightToken{
                .start_byte = start,
                .end_byte = byte_offset,
                .line = line,
                .group = .comment,
            });
        }
    }

    return tokens.toOwnedSlice(allocator);
}

fn isAlphanumeric(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9');
}

fn isKeyword(word: []const u8, keywords: []const []const u8) bool {
    for (keywords) |kw| {
        if (std.mem.eql(u8, word, kw)) {
            return true;
        }
    }
    return false;
}

fn getKeywords(language: Language) []const []const u8 {
    return switch (language) {
        .zig => &[_][]const u8{
            "const", "var", "fn", "pub", "struct", "enum", "union",
            "if", "else", "while", "for", "switch", "return", "break",
            "continue", "defer", "try", "catch", "comptime", "inline",
            "export", "extern", "packed", "anytype", "void", "bool",
            "u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64",
            "f32", "f64", "usize", "isize", "true", "false", "null",
        },
        .c => &[_][]const u8{
            "int", "char", "float", "double", "void", "struct", "enum",
            "if", "else", "while", "for", "switch", "return", "break",
            "continue", "const", "static", "extern", "typedef", "sizeof",
        },
        .rust => &[_][]const u8{
            "fn", "let", "mut", "const", "struct", "enum", "impl", "trait",
            "if", "else", "while", "for", "loop", "match", "return", "break",
            "continue", "pub", "use", "mod", "crate", "self", "super",
        },
        .go => &[_][]const u8{
            "func", "var", "const", "type", "struct", "interface",
            "if", "else", "for", "switch", "return", "break", "continue",
            "go", "defer", "package", "import", "chan", "map", "range",
        },
        .python => &[_][]const u8{
            "def", "class", "if", "elif", "else", "while", "for", "return",
            "break", "continue", "import", "from", "as", "try", "except",
            "finally", "with", "lambda", "yield", "async", "await",
        },
        else => &[_][]const u8{},
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
