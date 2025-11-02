//! Simple syntax highlighting without tree-sitter
//! Uses regex-like pattern matching for keywords, strings, comments

const std = @import("std");
const Color = @import("../render/buffer.zig").Color;

/// Token type for syntax highlighting
pub const TokenType = enum {
    normal,
    keyword,
    type_name,
    function_name,
    string,
    number,
    comment,
    operator,
    punctuation,
};

/// Get color for token type
pub fn getTokenColor(token_type: TokenType) Color {
    return switch (token_type) {
        .normal => Color.default,
        .keyword => Color.magenta,
        .type_name => Color.cyan,
        .function_name => Color.yellow,
        .string => Color.green,
        .number => Color.bright_blue,
        .comment => Color.bright_black,
        .operator => Color.bright_white,
        .punctuation => Color.white,
    };
}

/// Language-specific keywords
pub const ZigKeywords = [_][]const u8{
    "const",  "var",      "fn",       "pub",     "return",
    "if",     "else",     "while",    "for",     "switch",
    "break",  "continue", "defer",    "errdefer", "try",
    "catch",  "async",    "await",    "suspend", "resume",
    "struct", "enum",     "union",    "error",   "comptime",
    "inline", "export",   "extern",   "packed",  "align",
    "test",   "and",      "or",       "orelse",  "null",
    "true",   "false",    "undefined",
};

/// Check if a word is a keyword
pub fn isKeyword(word: []const u8, keywords: []const []const u8) bool {
    for (keywords) |keyword| {
        if (std.mem.eql(u8, word, keyword)) {
            return true;
        }
    }
    return false;
}

/// Simple tokenizer for a line
pub fn tokenizeLine(allocator: std.mem.Allocator, line: []const u8, language: Language) ![]Token {
    var tokens = std.ArrayList(Token).empty;
    errdefer tokens.deinit(allocator);

    var i: usize = 0;
    while (i < line.len) {
        // Skip whitespace
        if (std.ascii.isWhitespace(line[i])) {
            i += 1;
            continue;
        }

        // Line comment (//)
        if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '/') {
            try tokens.append(allocator, .{
                .type = .comment,
                .start = i,
                .end = line.len,
            });
            break; // Rest of line is comment
        }

        // String literals
        if (line[i] == '"') {
            const start = i;
            i += 1;
            while (i < line.len and line[i] != '"') {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 2; // Skip escaped character
                } else {
                    i += 1;
                }
            }
            if (i < line.len) i += 1; // Include closing quote
            try tokens.append(allocator, .{
                .type = .string,
                .start = start,
                .end = i,
            });
            continue;
        }

        // Character literals
        if (line[i] == '\'') {
            const start = i;
            i += 1;
            if (i < line.len and line[i] == '\\') i += 1; // Escape sequence
            if (i < line.len) i += 1; // Character
            if (i < line.len and line[i] == '\'') i += 1; // Closing quote
            try tokens.append(allocator, .{
                .type = .string,
                .start = start,
                .end = i,
            });
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(line[i])) {
            const start = i;
            while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '.')) {
                i += 1;
            }
            try tokens.append(allocator, .{
                .type = .number,
                .start = start,
                .end = i,
            });
            continue;
        }

        // Identifiers (keywords, types, functions)
        if (std.ascii.isAlphabetic(line[i]) or line[i] == '_' or line[i] == '@') {
            const start = i;
            while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '_')) {
                i += 1;
            }

            const word = line[start..i];
            const token_type = classifyWord(word, language);

            try tokens.append(allocator, .{
                .type = token_type,
                .start = start,
                .end = i,
            });
            continue;
        }

        // Operators and punctuation
        if (std.mem.indexOfScalar(u8, "+-*/%=<>!&|^~", line[i]) != null) {
            try tokens.append(allocator, .{
                .type = .operator,
                .start = i,
                .end = i + 1,
            });
            i += 1;
            continue;
        }

        // Default: punctuation
        try tokens.append(allocator, .{
            .type = .punctuation,
            .start = i,
            .end = i + 1,
        });
        i += 1;
    }

    return tokens.toOwnedSlice(allocator);
}

/// Classify a word as keyword, type, or identifier
fn classifyWord(word: []const u8, language: Language) TokenType {
    const keywords = switch (language) {
        .zig => &ZigKeywords,
        .unknown => &[_][]const u8{},
    };

    if (isKeyword(word, keywords)) {
        return .keyword;
    }

    // Simple heuristic: capitalized = type
    if (word.len > 0 and std.ascii.isUpper(word[0])) {
        return .type_name;
    }

    return .normal;
}

/// Token with position
pub const Token = struct {
    type: TokenType,
    start: usize,
    end: usize,
};

/// Supported languages
pub const Language = enum {
    zig,
    unknown,

    pub fn fromFilename(filename: []const u8) Language {
        if (std.mem.endsWith(u8, filename, ".zig")) return .zig;
        return .unknown;
    }
};

// === Tests ===

test "tokenize: keywords" {
    const allocator = std.testing.allocator;

    const line = "const x = 5;";
    const tokens = try tokenizeLine(allocator, line, .zig);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len > 0);
    try std.testing.expectEqual(TokenType.keyword, tokens[0].type);
}

test "tokenize: string literal" {
    const allocator = std.testing.allocator;

    const line = "const s = \"hello\";";
    const tokens = try tokenizeLine(allocator, line, .zig);
    defer allocator.free(tokens);

    var found_string = false;
    for (tokens) |token| {
        if (token.type == .string) {
            found_string = true;
        }
    }
    try std.testing.expect(found_string);
}

test "tokenize: comment" {
    const allocator = std.testing.allocator;

    const line = "const x = 5; // comment";
    const tokens = try tokenizeLine(allocator, line, .zig);
    defer allocator.free(tokens);

    try std.testing.expectEqual(TokenType.comment, tokens[tokens.len - 1].type);
}

test "tokenize: number" {
    const allocator = std.testing.allocator;

    const line = "const x = 123;";
    const tokens = try tokenizeLine(allocator, line, .zig);
    defer allocator.free(tokens);

    var found_number = false;
    for (tokens) |token| {
        if (token.type == .number) {
            found_number = true;
        }
    }
    try std.testing.expect(found_number);
}
