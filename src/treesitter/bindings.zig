//! Tree-sitter C API bindings
//! Provides Zig bindings to the tree-sitter parsing library
//!
//! Tree-sitter must be available either as:
//! 1. System library (libtree-sitter)
//! 2. Compiled from source as part of build
//!
//! Reference: https://tree-sitter.github.io/tree-sitter/using-parsers

const std = @import("std");

/// Opaque pointer to TSParser
pub const TSParser = opaque {};

/// Opaque pointer to TSTree
pub const TSTree = opaque {};

/// Opaque pointer to TSQuery
pub const TSQuery = opaque {};

/// Opaque pointer to TSQueryCursor
pub const TSQueryCursor = opaque {};

/// Opaque pointer to TSLanguage
pub const TSLanguage = opaque {};

/// TSNode represents a node in the syntax tree
pub const TSNode = extern struct {
    context: [4]u32,
    id: ?*const anyopaque,
    tree: ?*const TSTree,

    /// Check if node is null
    pub fn isNull(self: TSNode) bool {
        return self.id == null;
    }
};

/// TSPoint represents a position in source code
pub const TSPoint = extern struct {
    row: u32,
    column: u32,
};

/// TSRange represents a range in source code
pub const TSRange = extern struct {
    start_point: TSPoint,
    end_point: TSPoint,
    start_byte: u32,
    end_byte: u32,
};

/// TSInput provides source text to the parser
pub const TSInput = extern struct {
    payload: ?*anyopaque,
    read: *const fn (
        payload: ?*anyopaque,
        byte_index: u32,
        position: TSPoint,
        bytes_read: *u32,
    ) callconv(.C) [*c]const u8,
    encoding: TSInputEncoding,
};

/// TSInputEncoding specifies the text encoding
pub const TSInputEncoding = enum(c_int) {
    TSInputEncodingUTF8 = 0,
    TSInputEncodingUTF16 = 1,
};

/// TSSymbolType categorizes grammar symbols
pub const TSSymbolType = enum(c_int) {
    TSSymbolTypeRegular = 0,
    TSSymbolTypeAnonymous = 1,
    TSSymbolTypeAuxiliary = 2,
};

/// TSQueryError indicates query parsing errors
pub const TSQueryError = enum(c_int) {
    TSQueryErrorNone = 0,
    TSQueryErrorSyntax = 1,
    TSQueryErrorNodeType = 2,
    TSQueryErrorField = 3,
    TSQueryErrorCapture = 4,
    TSQueryErrorStructure = 5,
    TSQueryErrorLanguage = 6,
};

/// TSQueryMatch represents a query match result
pub const TSQueryMatch = extern struct {
    id: u32,
    pattern_index: u16,
    capture_count: u16,
    captures: [*c]const TSQueryCapture,
};

/// TSQueryCapture represents a captured node
pub const TSQueryCapture = extern struct {
    node: TSNode,
    index: u32,
};

// === Parser API ===

/// Create a new parser
pub extern fn ts_parser_new() ?*TSParser;

/// Delete a parser
pub extern fn ts_parser_delete(parser: *TSParser) void;

/// Set the language for parsing
pub extern fn ts_parser_set_language(parser: *TSParser, language: *const TSLanguage) bool;

/// Get the current language
pub extern fn ts_parser_language(parser: *const TSParser) ?*const TSLanguage;

/// Parse a string
pub extern fn ts_parser_parse_string(
    parser: *TSParser,
    old_tree: ?*TSTree,
    string: [*]const u8,
    length: u32,
) ?*TSTree;

/// Parse with a custom input
pub extern fn ts_parser_parse(
    parser: *TSParser,
    old_tree: ?*TSTree,
    input: TSInput,
) ?*TSTree;

/// Set timeout for parsing (microseconds)
pub extern fn ts_parser_set_timeout_micros(parser: *TSParser, timeout: u64) void;

/// Get current timeout
pub extern fn ts_parser_timeout_micros(parser: *const TSParser) u64;

// === Tree API ===

/// Delete a tree
pub extern fn ts_tree_delete(tree: *TSTree) void;

/// Create a copy of a tree
pub extern fn ts_tree_copy(tree: *const TSTree) ?*TSTree;

/// Get the root node of the tree
pub extern fn ts_tree_root_node(tree: *const TSTree) TSNode;

/// Get the language used to parse the tree
pub extern fn ts_tree_language(tree: *const TSTree) *const TSLanguage;

/// Edit the tree for incremental parsing
pub extern fn ts_tree_edit(tree: *TSTree, edit: *const TSInputEdit) void;

/// TSInputEdit describes a text edit
pub const TSInputEdit = extern struct {
    start_byte: u32,
    old_end_byte: u32,
    new_end_byte: u32,
    start_point: TSPoint,
    old_end_point: TSPoint,
    new_end_point: TSPoint,
};

// === Node API ===

/// Get the type of a node
pub extern fn ts_node_type(node: TSNode) [*:0]const u8;

/// Get the symbol ID of a node
pub extern fn ts_node_symbol(node: TSNode) u16;

/// Get the start byte of a node
pub extern fn ts_node_start_byte(node: TSNode) u32;

/// Get the end byte of a node
pub extern fn ts_node_end_byte(node: TSNode) u32;

/// Get the start point of a node
pub extern fn ts_node_start_point(node: TSNode) TSPoint;

/// Get the end point of a node
pub extern fn ts_node_end_point(node: TSNode) TSPoint;

/// Get the child count of a node
pub extern fn ts_node_child_count(node: TSNode) u32;

/// Get a child by index
pub extern fn ts_node_child(node: TSNode, index: u32) TSNode;

/// Get a named child by index
pub extern fn ts_node_named_child(node: TSNode, index: u32) TSNode;

/// Get the named child count
pub extern fn ts_node_named_child_count(node: TSNode) u32;

/// Get the next sibling
pub extern fn ts_node_next_sibling(node: TSNode) TSNode;

/// Get the previous sibling
pub extern fn ts_node_prev_sibling(node: TSNode) TSNode;

/// Get the parent node
pub extern fn ts_node_parent(node: TSNode) TSNode;

/// Check if node is named
pub extern fn ts_node_is_named(node: TSNode) bool;

/// Check if node is missing (error recovery)
pub extern fn ts_node_is_missing(node: TSNode) bool;

/// Check if node is extra
pub extern fn ts_node_is_extra(node: TSNode) bool;

/// Check if node has changes
pub extern fn ts_node_has_changes(node: TSNode) bool;

/// Check if node has error
pub extern fn ts_node_has_error(node: TSNode) bool;

/// Get node string (for debugging)
pub extern fn ts_node_string(node: TSNode) [*:0]u8;

// === Query API ===

/// Create a query from S-expression
pub extern fn ts_query_new(
    language: *const TSLanguage,
    source: [*]const u8,
    source_len: u32,
    error_offset: *u32,
    error_type: *TSQueryError,
) ?*TSQuery;

/// Delete a query
pub extern fn ts_query_delete(query: *TSQuery) void;

/// Get pattern count
pub extern fn ts_query_pattern_count(query: *const TSQuery) u32;

/// Get capture count
pub extern fn ts_query_capture_count(query: *const TSQuery) u32;

/// Get capture name
pub extern fn ts_query_capture_name_for_id(
    query: *const TSQuery,
    id: u32,
    length: *u32,
) [*]const u8;

/// Create a query cursor
pub extern fn ts_query_cursor_new() ?*TSQueryCursor;

/// Delete a query cursor
pub extern fn ts_query_cursor_delete(cursor: *TSQueryCursor) void;

/// Execute a query
pub extern fn ts_query_cursor_exec(
    cursor: *TSQueryCursor,
    query: *const TSQuery,
    node: TSNode,
) void;

/// Get next match
pub extern fn ts_query_cursor_next_match(
    cursor: *TSQueryCursor,
    match: *TSQueryMatch,
) bool;

// === Language API ===

/// Get language version
pub extern fn ts_language_version(language: *const TSLanguage) u32;

/// Get symbol count
pub extern fn ts_language_symbol_count(language: *const TSLanguage) u32;

/// Get symbol name
pub extern fn ts_language_symbol_name(
    language: *const TSLanguage,
    symbol: u16,
) [*:0]const u8;

/// Get symbol type
pub extern fn ts_language_symbol_type(
    language: *const TSLanguage,
    symbol: u16,
) TSSymbolType;

// === Language-specific functions (to be provided by grammar libraries) ===

/// Zig language
pub extern fn tree_sitter_zig() *const TSLanguage;

/// Rust language
pub extern fn tree_sitter_rust() *const TSLanguage;

/// Go language
pub extern fn tree_sitter_go() *const TSLanguage;

/// Python language
pub extern fn tree_sitter_python() *const TSLanguage;

/// C language
pub extern fn tree_sitter_c() *const TSLanguage;

/// Markdown language (block-level parsing)
pub extern fn tree_sitter_markdown() *const TSLanguage;

/// Markdown inline content (inline-level parsing)
pub extern fn tree_sitter_markdown_inline() *const TSLanguage;

// === Tests ===

test "TSNode size" {
    // Verify struct size matches C layout
    try std.testing.expectEqual(32, @sizeOf(TSNode));
}

test "TSPoint size" {
    try std.testing.expectEqual(8, @sizeOf(TSPoint));
}

test "TSRange size" {
    try std.testing.expectEqual(24, @sizeOf(TSRange));
}
