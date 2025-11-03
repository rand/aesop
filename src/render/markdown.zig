//! Simple markdown-to-plain-text converter for LSP hover content
//! Supports: headers, bold, italic, code blocks, lists, code spans

const std = @import("std");

/// Convert markdown to plain text with basic formatting
pub fn toPlainText(allocator: std.mem.Allocator, markdown: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    var in_code_block = false;
    var line_start = true;

    while (i < markdown.len) {
        // Code blocks (```)
        if (i + 2 < markdown.len and markdown[i] == '`' and markdown[i + 1] == '`' and markdown[i + 2] == '`') {
            in_code_block = !in_code_block;
            i += 3;
            // Skip language identifier on opening
            if (in_code_block) {
                while (i < markdown.len and markdown[i] != '\n') : (i += 1) {}
                if (i < markdown.len) i += 1; // Skip newline
            }
            try result.append(allocator, '\n');
            line_start = true;
            continue;
        }

        // Headers (# ## ###)
        if (line_start and i < markdown.len and markdown[i] == '#') {
            var level: usize = 0;
            while (i < markdown.len and markdown[i] == '#') : (i += 1) {
                level += 1;
            }
            // Skip space after #
            if (i < markdown.len and markdown[i] == ' ') i += 1;
            // Add header marker
            try result.appendSlice(allocator, "== ");
            line_start = false;
            continue;
        }

        // Lists (- or * or number.)
        if (line_start and i < markdown.len and (markdown[i] == '-' or markdown[i] == '*')) {
            try result.appendSlice(allocator, "  • ");
            i += 1;
            if (i < markdown.len and markdown[i] == ' ') i += 1;
            line_start = false;
            continue;
        }

        // Code spans (`code`)
        if (i < markdown.len and markdown[i] == '`') {
            i += 1;
            while (i < markdown.len and markdown[i] != '`') : (i += 1) {
                try result.append(allocator, markdown[i]);
            }
            if (i < markdown.len) i += 1; // Skip closing `
            line_start = false;
            continue;
        }

        // Bold (**text** or __text__)
        if (i + 1 < markdown.len and ((markdown[i] == '*' and markdown[i + 1] == '*') or
            (markdown[i] == '_' and markdown[i + 1] == '_')))
        {
            const marker = markdown[i];
            i += 2; // Skip **
            const start = i;
            // Find closing **
            while (i + 1 < markdown.len and !(markdown[i] == marker and markdown[i + 1] == marker)) : (i += 1) {}
            // Copy bold text (no special formatting in plain text)
            try result.appendSlice(allocator, markdown[start..i]);
            if (i + 1 < markdown.len) i += 2; // Skip closing **
            line_start = false;
            continue;
        }

        // Italic (*text* or _text_)
        if (i < markdown.len and (markdown[i] == '*' or markdown[i] == '_')) {
            const marker = markdown[i];
            i += 1; // Skip *
            const start = i;
            // Find closing *
            while (i < markdown.len and markdown[i] != marker) : (i += 1) {}
            // Copy italic text (no special formatting in plain text)
            try result.appendSlice(allocator, markdown[start..i]);
            if (i < markdown.len) i += 1; // Skip closing *
            line_start = false;
            continue;
        }

        // Links ([text](url))
        if (i < markdown.len and markdown[i] == '[') {
            const text_start = i + 1;
            i += 1;
            // Find closing ]
            while (i < markdown.len and markdown[i] != ']') : (i += 1) {}
            const text_end = i;
            if (i < markdown.len) i += 1; // Skip ]

            // Skip URL part
            if (i < markdown.len and markdown[i] == '(') {
                i += 1;
                while (i < markdown.len and markdown[i] != ')') : (i += 1) {}
                if (i < markdown.len) i += 1; // Skip )
            }

            // Just use the link text
            try result.appendSlice(allocator, markdown[text_start..text_end]);
            line_start = false;
            continue;
        }

        // Newlines
        if (i < markdown.len and markdown[i] == '\n') {
            try result.append(allocator, '\n');
            i += 1;
            line_start = true;
            continue;
        }

        // Regular character
        if (i < markdown.len) {
            try result.append(allocator, markdown[i]);
            line_start = false;
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Format code block with basic indentation
pub fn formatCodeBlock(allocator: std.mem.Allocator, code: []const u8, language: []const u8) ![]const u8 {
    _ = language; // For future syntax highlighting

    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, "Code:\n");

    var i: usize = 0;
    while (i < code.len) {
        if (code[i] == '\n' or i == 0) {
            if (i > 0) try result.append(allocator, '\n');
            try result.appendSlice(allocator, "  ");
            if (code[i] == '\n') i += 1;
        } else {
            try result.append(allocator, code[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

// === Tests ===

test "markdown: headers" {
    const allocator = std.testing.allocator;

    const input = "# Header 1\n## Header 2\n### Header 3";
    const output = try toPlainText(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "==") != null);
}

test "markdown: code spans" {
    const allocator = std.testing.allocator;

    const input = "Use `std.debug.print` for logging";
    const output = try toPlainText(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "std.debug.print") != null);
}

test "markdown: bold" {
    const allocator = std.testing.allocator;

    const input = "This is **bold** text";
    const output = try toPlainText(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "bold") != null);
}

test "markdown: lists" {
    const allocator = std.testing.allocator;

    const input = "- Item 1\n- Item 2\n* Item 3";
    const output = try toPlainText(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "•") != null);
}

test "markdown: code block" {
    const allocator = std.testing.allocator;

    const input = "```zig\nconst x = 5;\n```";
    const output = try toPlainText(allocator, input);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "const x = 5") != null);
}
