//! Tree-sitter integration for syntax highlighting
//! Provides incremental parsing and syntax tree queries

const std = @import("std");
const Buffer = @import("../buffer/manager.zig").Buffer;
const Highlight = @import("highlight.zig");
const ts = @import("../treesitter/bindings.zig");

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

    /// Convert to renderer color using theme
    pub fn toColor(self: HighlightGroup, theme: *const @import("theme.zig").Theme) @import("../render/buffer.zig").Color {
        return switch (self) {
            .keyword => theme.syntax.keyword,
            .function_name => theme.syntax.function_name,
            .type_name => theme.syntax.type_name,
            .variable => theme.syntax.variable,
            .constant => theme.syntax.constant,
            .string => theme.syntax.string,
            .number => theme.syntax.number,
            .comment => theme.syntax.comment,
            .operator => theme.syntax.operator,
            .punctuation => theme.syntax.punctuation,
            .error_node => theme.syntax.error_node,
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
    tsx,
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
        if (std.mem.endsWith(u8, filename, ".tsx")) return .tsx; // Check .tsx before .ts
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
            .tsx => "tsx",
            .json => "json",
            .markdown => "markdown",
            .plain_text => "plain_text",
        };
    }
};

/// Load and compile a highlight query for a language
fn loadHighlightQuery(
    allocator: std.mem.Allocator,
    ts_language: *const ts.TSLanguage,
    language: Language,
) !*ts.TSQuery {
    // Construct path to query file: queries/{language}/highlights.scm
    const lang_name = language.getName();
    const query_path = try std.fmt.allocPrint(
        allocator,
        "queries/{s}/highlights.scm",
        .{lang_name},
    );
    defer allocator.free(query_path);

    // Read query file
    const query_source = std.fs.cwd().readFileAlloc(
        allocator,
        query_path,
        1024 * 1024, // Max 1MB query file
    ) catch |err| {
        std.debug.print("Failed to read query file '{s}': {}\n", .{ query_path, err });
        return error.QueryFileNotFound;
    };
    defer allocator.free(query_source);

    // Compile query
    var error_offset: u32 = 0;
    var error_type: ts.TSQueryError = .TSQueryErrorNone;

    const query = ts.ts_query_new(
        ts_language,
        query_source.ptr,
        @intCast(query_source.len),
        &error_offset,
        &error_type,
    ) orelse {
        std.debug.print("Query compilation failed at offset {d}: {}\n", .{ error_offset, error_type });
        return error.QueryCompilationFailed;
    };

    return query;
}

/// Map tree-sitter capture name to HighlightGroup
fn captureNameToHighlightGroup(capture_name: []const u8) HighlightGroup {
    // Map common capture names to highlight groups
    if (std.mem.eql(u8, capture_name, "keyword")) return .keyword;
    if (std.mem.eql(u8, capture_name, "keyword.operator")) return .keyword;
    if (std.mem.eql(u8, capture_name, "function.definition")) return .function_name;
    if (std.mem.eql(u8, capture_name, "function.call")) return .function_name;
    if (std.mem.eql(u8, capture_name, "function.builtin")) return .function_name;
    if (std.mem.eql(u8, capture_name, "type.builtin")) return .type_name;
    if (std.mem.eql(u8, capture_name, "type.definition")) return .type_name;
    if (std.mem.eql(u8, capture_name, "constant")) return .constant;
    if (std.mem.eql(u8, capture_name, "constant.builtin")) return .constant;
    if (std.mem.eql(u8, capture_name, "string")) return .string;
    if (std.mem.eql(u8, capture_name, "string.special")) return .string;
    if (std.mem.eql(u8, capture_name, "number")) return .number;
    if (std.mem.eql(u8, capture_name, "comment")) return .comment;
    if (std.mem.eql(u8, capture_name, "operator")) return .operator;
    if (std.mem.eql(u8, capture_name, "punctuation.delimiter")) return .punctuation;
    if (std.mem.eql(u8, capture_name, "error")) return .error_node;

    // Default to variable for unknown captures
    return .variable;
}

/// Convert byte position to TSPoint (line, column)
fn byteToPoint(text: []const u8, byte_pos: usize) ts.TSPoint {
    var line: u32 = 0;
    var col: u32 = 0;
    var i: usize = 0;

    while (i < byte_pos and i < text.len) : (i += 1) {
        if (text[i] == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
    }

    return ts.TSPoint{ .row = line, .column = col };
}

/// Create TSInputEdit for an insertion
pub fn createInsertEdit(text: []const u8, pos: usize, inserted_text: []const u8) ts.TSInputEdit {
    const start_point = byteToPoint(text, pos);

    // Calculate end point (after insertion)
    var end_line = start_point.row;
    var end_col = start_point.column;

    for (inserted_text) |ch| {
        if (ch == '\n') {
            end_line += 1;
            end_col = 0;
        } else {
            end_col += 1;
        }
    }

    return ts.TSInputEdit{
        .start_byte = @intCast(pos),
        .old_end_byte = @intCast(pos), // Insertion: old_end == start
        .new_end_byte = @intCast(pos + inserted_text.len),
        .start_point = start_point,
        .old_end_point = start_point, // Insertion: old_end_point == start_point
        .new_end_point = ts.TSPoint{ .row = end_line, .column = end_col },
    };
}

/// Create TSInputEdit for a deletion
pub fn createDeleteEdit(text: []const u8, start: usize, end: usize) ts.TSInputEdit {
    const start_point = byteToPoint(text, start);
    const old_end_point = byteToPoint(text, end);

    return ts.TSInputEdit{
        .start_byte = @intCast(start),
        .old_end_byte = @intCast(end),
        .new_end_byte = @intCast(start), // Deletion: new_end == start
        .start_point = start_point,
        .old_end_point = old_end_point,
        .new_end_point = start_point, // Deletion: new_end_point == start_point
    };
}

/// Create TSInputEdit for a replacement
pub fn createReplaceEdit(
    text: []const u8,
    start: usize,
    end: usize,
    new_text: []const u8,
) ts.TSInputEdit {
    const start_point = byteToPoint(text, start);
    const old_end_point = byteToPoint(text, end);

    // Calculate new end point
    var new_end_line = start_point.row;
    var new_end_col = start_point.column;

    for (new_text) |ch| {
        if (ch == '\n') {
            new_end_line += 1;
            new_end_col = 0;
        } else {
            new_end_col += 1;
        }
    }

    return ts.TSInputEdit{
        .start_byte = @intCast(start),
        .old_end_byte = @intCast(end),
        .new_end_byte = @intCast(start + new_text.len),
        .start_point = start_point,
        .old_end_point = old_end_point,
        .new_end_point = ts.TSPoint{ .row = new_end_line, .column = new_end_col },
    };
}

/// Get tree-sitter language grammar for a Language
/// Returns the grammar function for supported languages
/// Note: Requires language-specific grammar libraries to be installed and linked
/// See build.zig and docs/BUILDING_WITH_TREE_SITTER.md for setup
fn getTreeSitterLanguage(language: Language) ?*const ts.TSLanguage {
    return switch (language) {
        // Supported languages with tree-sitter grammars
        .zig => ts.tree_sitter_zig(),
        .c => ts.tree_sitter_c(),
        .rust => ts.tree_sitter_rust(),
        .go => ts.tree_sitter_go(),
        .python => ts.tree_sitter_python(),
        .markdown => ts.tree_sitter_markdown(),
        .typescript => ts.tree_sitter_typescript(),
        .tsx => ts.tree_sitter_tsx(),

        // These don't have tree-sitter grammars in our bindings yet
        .javascript,
        .json,
        .plain_text,
        => null,
    };
}

/// Parser state - manages syntax tree for a buffer
pub const Parser = struct {
    language: Language,
    allocator: std.mem.Allocator,
    ts_parser: ?*ts.TSParser,
    ts_tree: ?*ts.TSTree,
    ts_language: ?*const ts.TSLanguage,
    ts_query: ?*ts.TSQuery,
    ts_query_cursor: ?*ts.TSQueryCursor,

    pub fn init(allocator: std.mem.Allocator, language: Language) !Parser {
        // Create tree-sitter parser
        const ts_parser = ts.ts_parser_new() orelse return error.ParserCreationFailed;
        errdefer ts.ts_parser_delete(ts_parser);

        // Get language grammar
        const ts_language = getTreeSitterLanguage(language);

        // Set language (if available)
        if (ts_language) |lang| {
            if (!ts.ts_parser_set_language(ts_parser, lang)) {
                ts.ts_parser_delete(ts_parser);
                return error.LanguageSetFailed;
            }
        }

        // Load and compile highlight query (if language grammar available)
        std.debug.print("DEBUG: Loading highlight query for language={s}\n", .{language.getName()});
        const ts_query: ?*ts.TSQuery = if (ts_language) |lang|
            loadHighlightQuery(allocator, lang, language) catch |err| blk: {
                std.debug.print("Warning: Failed to load highlight query: {}\n", .{err});
                break :blk null;
            }
        else
            null;
        std.debug.print("DEBUG: Query loaded: {}\n", .{ts_query != null});

        // Create query cursor (if we have a query)
        var ts_query_cursor: ?*ts.TSQueryCursor = null;
        if (ts_query != null) {
            ts_query_cursor = ts.ts_query_cursor_new();
        }

        return .{
            .language = language,
            .allocator = allocator,
            .ts_parser = ts_parser,
            .ts_tree = null,
            .ts_language = ts_language,
            .ts_query = ts_query,
            .ts_query_cursor = ts_query_cursor,
        };
    }

    pub fn deinit(self: *Parser) void {
        if (self.ts_query_cursor) |cursor| {
            ts.ts_query_cursor_delete(cursor);
        }
        if (self.ts_query) |query| {
            ts.ts_query_delete(query);
        }
        if (self.ts_tree) |tree| {
            ts.ts_tree_delete(tree);
        }
        if (self.ts_parser) |parser| {
            ts.ts_parser_delete(parser);
        }
    }

    /// Parse buffer and create/update syntax tree
    pub fn parse(self: *Parser, text: []const u8) !void {
        std.debug.print("DEBUG: parse() called for language={s}, text_len={}\n", .{ self.language.getName(), text.len });
        const parser = self.ts_parser orelse {
            std.debug.print("DEBUG: No parser available\n", .{});
            return error.NoParser;
        };

        // Parse the text (uses old tree for incremental parsing)
        const new_tree = ts.ts_parser_parse_string(
            parser,
            self.ts_tree, // old tree for incremental parsing
            text.ptr,
            @intCast(text.len),
        ) orelse {
            std.debug.print("DEBUG: Parse failed\n", .{});
            return error.ParseFailed;
        };

        std.debug.print("DEBUG: Parse succeeded, tree created\n", .{});

        // Delete old tree if it exists
        if (self.ts_tree) |old_tree| {
            ts.ts_tree_delete(old_tree);
        }

        self.ts_tree = new_tree;
    }

    /// Apply an edit to the syntax tree for incremental parsing
    /// Call this before re-parsing after a text change
    pub fn applyEdit(self: *Parser, edit: ts.TSInputEdit) void {
        if (self.ts_tree) |tree| {
            ts.ts_tree_edit(tree, &edit);
        }
    }

    /// Get highlights for a line range using tree-sitter queries
    pub fn getHighlights(
        self: *Parser,
        text: []const u8,
        start_line: usize,
        end_line: usize,
    ) ![]HighlightToken {
        _ = start_line;
        _ = end_line;

        std.debug.print("DEBUG: getHighlights called for language={s}, text_len={}\n", .{ self.language.getName(), text.len });
        std.debug.print("DEBUG: ts_query={}, ts_query_cursor={}, ts_tree={}\n", .{ self.ts_query != null, self.ts_query_cursor != null, self.ts_tree != null });

        // If query-based highlighting is not available, fall back to basic highlighting
        if (self.ts_query == null or self.ts_query_cursor == null or self.ts_tree == null) {
            std.debug.print("DEBUG: Using basicHighlight fallback\n", .{});
            return try basicHighlight(self.allocator, text, self.language);
        }

        std.debug.print("DEBUG: Using tree-sitter query-based highlighting\n", .{});

        const query = self.ts_query.?;
        const cursor = self.ts_query_cursor.?;
        const tree = self.ts_tree.?;

        // Get root node
        const root_node = ts.ts_tree_root_node(tree);

        // Execute query on root node
        ts.ts_query_cursor_exec(cursor, query, root_node);

        // Collect all matches
        var tokens = std.ArrayList(HighlightToken).empty;
        errdefer tokens.deinit(self.allocator);

        var match: ts.TSQueryMatch = undefined;
        while (ts.ts_query_cursor_next_match(cursor, &match)) {
            // Process each capture in the match
            const captures = match.captures[0..match.capture_count];
            for (captures) |capture| {
                // Get capture name
                var name_len: u32 = 0;
                const name_ptr = ts.ts_query_capture_name_for_id(
                    query,
                    capture.index,
                    &name_len,
                );
                const capture_name = name_ptr[0..name_len];

                // Map capture name to highlight group
                const group = captureNameToHighlightGroup(capture_name);

                // Get node position
                const start_byte = ts.ts_node_start_byte(capture.node);
                const end_byte = ts.ts_node_end_byte(capture.node);
                const start_point = ts.ts_node_start_point(capture.node);

                // Create highlight token
                try tokens.append(self.allocator, HighlightToken{
                    .start_byte = start_byte,
                    .end_byte = end_byte,
                    .line = start_point.row,
                    .group = group,
                });
            }
        }

        return tokens.toOwnedSlice(self.allocator);
    }
};

/// Basic regex-free keyword highlighting (temporary until tree-sitter is integrated)
/// Uses the enhanced tokenizer from highlight.zig
fn basicHighlight(allocator: std.mem.Allocator, text: []const u8, language: Language) ![]HighlightToken {
    // For unsupported languages (plain_text, etc.), return empty array
    // This prevents incorrect highlighting of non-code text
    const highlight_lang = switch (language) {
        .zig => Highlight.Language.zig,
        .plain_text => return &[_]HighlightToken{}, // No highlighting for plain text files
        else => Highlight.Language.unknown,
    };

    var tokens = std.ArrayList(HighlightToken).empty;
    errdefer tokens.deinit(allocator);

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
