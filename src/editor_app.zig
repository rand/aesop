//! Working editor application
//! Integrates all components into a functional text editor

const std = @import("std");
const Editor = @import("editor/editor.zig").Editor;
const Cursor = @import("editor/cursor.zig");
const renderer_mod = @import("render/renderer.zig");
const Renderer = renderer_mod.Renderer;
const Attrs = renderer_mod.Attrs;
const Cell = renderer_mod.Cell;
const statusline = @import("render/statusline.zig");
const messageline = @import("render/messageline.zig");
const keyhints = @import("render/keyhints.zig");
const paletteline = @import("render/paletteline.zig");
const gutter = @import("render/gutter.zig");
const input_mod = @import("terminal/input.zig");
const Keymap = @import("editor/keymap.zig");
const TreeSitter = @import("editor/treesitter.zig");

/// Editor application
pub const EditorApp = struct {
    editor: Editor,
    renderer: Renderer,
    allocator: std.mem.Allocator,
    running: bool,
    gutter_config: gutter.GutterConfig,
    mouse_drag_start: ?Cursor.Position,
    syntax_parser: ?TreeSitter.Parser,
    syntax_enabled: bool,

    /// Initialize editor application
    pub fn init(allocator: std.mem.Allocator) !EditorApp {
        var editor = try Editor.init(allocator);
        errdefer editor.deinit();

        var renderer = try Renderer.init(allocator);
        errdefer renderer.deinit();

        return .{
            .editor = editor,
            .renderer = renderer,
            .allocator = allocator,
            .running = false,
            .gutter_config = .{},
            .mouse_drag_start = null,
            .syntax_parser = null,
            .syntax_enabled = true, // Default: syntax highlighting on
        };
    }

    /// Clean up
    pub fn deinit(self: *EditorApp) void {
        if (self.syntax_parser) |*parser| {
            parser.deinit();
        }
        self.editor.deinit();
        self.renderer.deinit();
    }

    /// Get or create parser for current buffer
    fn ensureParser(self: *EditorApp) !void {
        // Get active buffer
        const buffer = self.editor.getActiveBuffer() orelse return;

        // Determine language from buffer name
        const buffer_name = buffer.metadata.getName();
        const language = TreeSitter.Language.fromFilename(buffer_name);

        // If we have a parser and it's for the right language, keep it
        if (self.syntax_parser) |existing| {
            if (existing.language == language) {
                return;
            }
            // Wrong language - cleanup and recreate
            var parser = self.syntax_parser.?;
            parser.deinit();
        }

        // Create new parser for this language
        self.syntax_parser = try TreeSitter.Parser.init(self.allocator, language);
    }

    /// Toggle syntax highlighting
    pub fn toggleSyntaxHighlighting(self: *EditorApp) void {
        self.syntax_enabled = !self.syntax_enabled;
    }

    /// Run the editor
    pub fn run(self: *EditorApp, filepath: ?[]const u8) !void {
        // Load file or create empty buffer
        if (filepath) |path| {
            try self.editor.openFile(path);
        } else {
            try self.editor.newBuffer();
        }

        // Enter raw mode
        try self.renderer.enterRawMode();
        defer self.renderer.exitRawMode() catch {};

        self.running = true;

        // Main event loop
        var input_buf: [64]u8 = undefined;
        var parser = input_mod.Parser{};

        while (self.running) {
            // Render
            try self.render();

            // Process input
            const n = try self.renderer.terminal.readInput(&input_buf);
            if (n > 0) {
                const events = try parser.parse(self.allocator, input_buf[0..n]);
                defer self.allocator.free(events);

                for (events) |event| {
                    try self.handleEvent(event);
                }
            }

            // Small sleep to avoid busy loop
            std.Thread.sleep(5 * std.time.ns_per_ms);
        }
    }

    /// Handle input event
    fn handleEvent(self: *EditorApp, event: input_mod.Event) !void {
        // Handle palette input separately
        if (self.editor.palette.visible) {
            try self.handlePaletteInput(event);
            return;
        }

        switch (event) {
            .char => |c| {
                // Convert to keymap key
                const key = Keymap.Key{ .char = c.codepoint };

                // Check for quit command (Ctrl+Q in normal mode)
                if (c.mods.ctrl and c.codepoint == 'q' and
                    self.editor.getMode() == .normal)
                {
                    self.running = false;
                    return;
                }

                // Process through editor
                try self.editor.processKey(key);
            },

            .key => |k| {
                // Convert special key to keymap key
                const key = Keymap.Key{ .special = k.key };

                // Escape always returns to normal mode
                if (k.key == .escape) {
                    try self.editor.enterNormalMode();
                    return;
                }

                // Process through editor
                try self.editor.processKey(key);
            },

            .resize => |r| {
                try self.renderer.handleResize();
                _ = r;
            },

            .mouse => |m| {
                try self.handleMouse(m);
            },

            else => {},
        }
    }

    /// Handle palette input
    fn handlePaletteInput(self: *EditorApp, event: input_mod.Event) !void {
        switch (event) {
            .char => |c| {
                // Add character to query
                try self.editor.palette.addChar(c.codepoint);
            },

            .key => |k| {
                switch (k.key) {
                    .escape => {
                        // Close palette
                        self.editor.palette.hide();
                    },
                    .backspace => {
                        // Remove last character
                        self.editor.palette.backspace();
                    },
                    .enter => {
                        // Execute selected command
                        try self.executePaletteCommand();
                    },
                    .up => {
                        // Move selection up
                        self.editor.palette.selectPrevious();
                    },
                    .down => {
                        // Move selection down
                        const matches = try self.editor.palette.filterCommands(&self.editor.command_registry, self.allocator);
                        defer self.allocator.free(matches);
                        self.editor.palette.selectNext(matches.len);
                    },
                    else => {},
                }
            },

            else => {},
        }
    }

    /// Execute the currently selected palette command
    fn executePaletteCommand(self: *EditorApp) !void {
        const matches = try self.editor.palette.filterCommands(&self.editor.command_registry, self.allocator);
        defer self.allocator.free(matches);

        if (matches.len == 0) return;

        const selected_idx = @min(self.editor.palette.selected_index, matches.len - 1);
        const command_name = matches[selected_idx].name;

        // Hide palette
        self.editor.palette.hide();

        // Execute command
        var ctx = @import("editor/command.zig").Context{ .editor = &self.editor };
        const result = self.editor.command_registry.execute(command_name, &ctx);

        switch (result) {
            .success => {},
            .error_msg => |msg| {
                self.editor.messages.add(msg, .error_msg) catch {};
            },
        }
    }

    /// Handle mouse events
    fn handleMouse(self: *EditorApp, mouse: anytype) !void {
        switch (mouse.kind) {
            .press_left => {
                try self.handleMousePress(mouse.row, mouse.col);
            },
            .move => {
                // Treat move as drag if we have a drag start position
                try self.handleMouseDrag(mouse.row, mouse.col);
            },
            .release => {
                self.handleMouseRelease();
            },
            else => {},
        }
    }

    /// Handle mouse press - start selection
    fn handleMousePress(self: *EditorApp, screen_row: u16, screen_col: u16) !void {
        const size = self.renderer.getSize();
        const buffer = self.editor.getActiveBuffer() orelse return;

        // Check if we have a message displayed
        const has_message = self.editor.messages.current() != null;
        const reserved_lines: usize = if (has_message) 2 else 1;

        // Ignore clicks on status/message lines
        if (screen_row >= size.height - reserved_lines) return;

        const viewport = self.editor.getViewport(size.height - reserved_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Ignore clicks in gutter
        if (screen_col < gutter_width) return;

        // Convert screen position to buffer position
        const buffer_line = viewport.start_line + screen_row;
        const buffer_col = screen_col - gutter_width;

        // Clamp to valid buffer position
        const total_lines = buffer.lineCount();
        if (buffer_line >= total_lines) return;

        // Create position
        const pos = Cursor.Position{
            .line = buffer_line,
            .col = buffer_col,
        };

        // Start drag tracking
        self.mouse_drag_start = pos;

        // Set cursor position
        try self.editor.selections.setSingleCursor(self.allocator, pos);

        // Return to normal mode if in visual mode
        if (self.editor.getMode() == .select) {
            try self.editor.enterNormalMode();
        }
    }

    /// Handle mouse drag - extend selection
    fn handleMouseDrag(self: *EditorApp, screen_row: u16, screen_col: u16) !void {
        const drag_start = self.mouse_drag_start orelse return;

        const size = self.renderer.getSize();
        const buffer = self.editor.getActiveBuffer() orelse return;

        // Check if we have a message displayed
        const has_message = self.editor.messages.current() != null;
        const reserved_lines: usize = if (has_message) 2 else 1;

        // Ignore drags on status/message lines
        if (screen_row >= size.height - reserved_lines) return;

        const viewport = self.editor.getViewport(size.height - reserved_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Ignore drags in gutter
        if (screen_col < gutter_width) return;

        // Convert screen position to buffer position
        const buffer_line = viewport.start_line + screen_row;
        const buffer_col = screen_col - gutter_width;

        // Clamp to valid buffer position
        const total_lines = buffer.lineCount();
        if (buffer_line >= total_lines) return;

        // Create drag end position
        const drag_end = Cursor.Position{
            .line = buffer_line,
            .col = buffer_col,
        };

        // Enter select mode if not already
        if (self.editor.getMode() != .select) {
            try self.editor.enterSelectMode();
        }

        // Create selection from drag start to drag end
        const selection = Cursor.Selection{
            .anchor = drag_start,
            .head = drag_end,
        };

        try self.editor.selections.setSingleSelection(self.allocator, selection);
    }

    /// Handle mouse release - finalize selection
    fn handleMouseRelease(self: *EditorApp) void {
        self.mouse_drag_start = null;
    }

    /// Render the editor
    fn render(self: *EditorApp) !void {
        // Clear screen
        self.renderer.clear();

        const size = self.renderer.getSize();

        // Check if we have a message to display
        const has_message = self.editor.messages.current() != null;
        const reserved_lines: usize = if (has_message) 2 else 1; // Message + status or just status

        // Render buffer content
        try self.renderBuffer(size.height -| reserved_lines);

        // Render gutter
        const viewport = self.editor.getViewport(size.height -| reserved_lines);
        const cursor_pos = self.editor.getCursorPosition();

        try gutter.render(
            &self.renderer,
            self.gutter_config,
            viewport.start_line,
            viewport.end_line,
            cursor_pos.line,
        );

        // Render message line (if message exists)
        _ = try messageline.render(&self.renderer, &self.editor);

        // Render status line
        try statusline.render(&self.renderer, &self.editor);

        // Render key hints (overlays on status line)
        try keyhints.render(&self.renderer, &self.editor);

        // Render cursor (if not in command palette)
        if (!self.editor.palette.visible) {
            try self.renderCursor(size.height - reserved_lines);
        }

        // Render command palette (overlay on top of everything)
        try paletteline.render(&self.renderer, &self.editor, self.allocator);

        // Perform render
        try self.renderer.render();
    }

    /// Render all cursors
    fn renderCursor(self: *EditorApp, visible_lines: usize) !void {
        const buffer = self.editor.getActiveBuffer() orelse return;
        const viewport = self.editor.getViewport(visible_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Render all cursors from all selections
        const selections = self.editor.selections.all(self.allocator);
        for (selections) |sel| {
            const cursor_pos = sel.head;

            // Check if cursor is in viewport
            if (cursor_pos.line < viewport.start_line or cursor_pos.line >= viewport.end_line) {
                continue; // Cursor is off-screen
            }

            // Calculate screen position
            const screen_row = @as(u16, @intCast(cursor_pos.line - viewport.start_line));
            const screen_col = gutter_width + @as(u16, @intCast(cursor_pos.col));

            // Get current cell at cursor position or create empty cell
            const cell = self.renderer.output.getCell(screen_row, screen_col) orelse Cell{
                .char = ' ',
                .fg = .default,
                .bg = .default,
                .attrs = .{},
            };

            // Set cursor with reverse video
            self.renderer.output.setCell(screen_row, screen_col, .{
                .char = cell.char,
                .fg = cell.bg, // Swap colors for cursor
                .bg = cell.fg,
                .attrs = .{ .reverse = true },
            });
        }
    }

    /// Render buffer content
    fn renderBuffer(self: *EditorApp, visible_lines: usize) !void {
        const buffer = self.editor.getActiveBuffer() orelse return;

        const viewport = self.editor.getViewport(visible_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Get selection (for highlighting)
        const primary_sel = self.editor.selections.primary(self.allocator) orelse return;
        const in_visual_mode = self.editor.getMode() == .select and !primary_sel.isCollapsed();
        const sel_range = if (in_visual_mode) primary_sel.range() else null;

        // Get buffer text
        const text = try buffer.getText();
        defer self.allocator.free(text);

        // Get search matches (for highlighting)
        const search_matches = if (self.editor.search.active)
            try self.editor.search.findAll(text, self.allocator)
        else
            &[_]@import("editor/search.zig").Search.Match{};
        defer if (self.editor.search.active) self.allocator.free(search_matches);

        // Get syntax highlights (if enabled)
        const syntax_highlights = if (self.syntax_enabled) blk: {
            try self.ensureParser();
            if (self.syntax_parser) |*parser| {
                break :blk try parser.getHighlights(text, viewport.start_line, viewport.end_line);
            }
            break :blk &[_]TreeSitter.HighlightToken{};
        } else &[_]TreeSitter.HighlightToken{};
        defer if (self.syntax_enabled and self.syntax_parser != null) self.allocator.free(syntax_highlights);

        // Simple line rendering (just display lines)
        var line_num: usize = viewport.start_line;
        var row: u16 = 0;
        var i: usize = 0;

        // Skip lines before viewport
        var current_line: usize = 0;
        while (i < text.len and current_line < viewport.start_line) {
            if (text[i] == '\n') {
                current_line += 1;
            }
            i += 1;
        }

        // Render visible lines
        while (i < text.len and line_num < viewport.end_line) {
            const line_start = i;
            var line_end = i;

            // Find end of line
            while (line_end < text.len and text[line_end] != '\n') {
                line_end += 1;
            }

            const line_text = text[line_start..line_end];

            // Check if this line has selection or search matches
            const line_has_selection = if (sel_range) |range|
                (line_num >= range.start.line and line_num <= range.end.line)
            else
                false;

            const line_has_search = blk: {
                for (search_matches) |match| {
                    if (line_num >= match.start.line and line_num <= match.end.line) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            const line_has_syntax = blk: {
                for (syntax_highlights) |token| {
                    if (token.line == line_num) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (line_has_selection or line_has_search or line_has_syntax) {
                // Render line character by character with highlighting
                try self.renderLineWithHighlights(
                    row,
                    gutter_width,
                    line_text,
                    line_num,
                    sel_range,
                    search_matches,
                    syntax_highlights,
                );
            } else {
                // Render line normally
                self.renderer.writeText(
                    row,
                    gutter_width,
                    line_text,
                    .default,
                    .default,
                    .{},
                );
            }

            // Move to next line
            i = if (line_end < text.len) line_end + 1 else line_end;
            line_num += 1;
            row += 1;

            if (row >= visible_lines) break;
        }
    }

    /// Render a line with selection, search, and syntax highlighting
    fn renderLineWithHighlights(
        self: *EditorApp,
        row: u16,
        start_col: u16,
        line_text: []const u8,
        line_num: usize,
        opt_sel_range: anytype,
        search_matches: []const @import("editor/search.zig").Search.Match,
        syntax_highlights: []const TreeSitter.HighlightToken,
    ) !void {
        var col: usize = 0;
        var screen_col = start_col;

        while (col < line_text.len) : (col += 1) {
            // Check if character is in selection
            const is_selected = if (opt_sel_range) |range| blk: {
                if (line_num == range.start.line and line_num == range.end.line) {
                    break :blk col >= range.start.col and col < range.end.col;
                } else if (line_num == range.start.line) {
                    break :blk col >= range.start.col;
                } else if (line_num == range.end.line) {
                    break :blk col < range.end.col;
                } else if (line_num > range.start.line and line_num < range.end.line) {
                    break :blk true;
                } else {
                    break :blk false;
                }
            } else false;

            // Check if character is in search match (only if not selected)
            const is_search_match = if (!is_selected) blk: {
                for (search_matches) |match| {
                    if (line_num == match.start.line and line_num == match.end.line) {
                        if (col >= match.start.col and col < match.end.col) {
                            break :blk true;
                        }
                    } else if (line_num == match.start.line) {
                        if (col >= match.start.col) break :blk true;
                    } else if (line_num == match.end.line) {
                        if (col < match.end.col) break :blk true;
                    } else if (line_num > match.start.line and line_num < match.end.line) {
                        break :blk true;
                    }
                }
                break :blk false;
            } else false;

            // Check for syntax highlighting (only if not selected or search matched)
            // Note: syntax tokens are on the current line, so we just need to match column
            const syntax_group: ?TreeSitter.HighlightGroup = if (!is_selected and !is_search_match) blk: {
                for (syntax_highlights) |token| {
                    // Tokens are byte-based, but we're doing simple char matching for now
                    // This works for ASCII; for full UTF-8 would need byte offset tracking
                    if (token.line == line_num) {
                        // Simplified: assume 1 byte per char (works for most code)
                        if (col >= token.start_byte and col < token.end_byte) {
                            break :blk token.group;
                        }
                    }
                }
                break :blk null;
            } else null;

            const char_slice = line_text[col .. col + 1];

            // Priority: selection > search match > syntax > normal
            if (is_selected) {
                // Selection: reverse video
                self.renderer.writeText(
                    row,
                    screen_col,
                    char_slice,
                    .default,
                    .default,
                    Attrs{ .reverse = true },
                );
            } else if (is_search_match) {
                // Search match: underline
                self.renderer.writeText(
                    row,
                    screen_col,
                    char_slice,
                    .default,
                    .default,
                    Attrs{ .underline = true },
                );
            } else if (syntax_group) |group| {
                // Syntax highlighting: use color from highlight group
                // TODO: Map highlight groups to proper renderer colors
                _ = group; // Unused for now - will be used when we add color support
                self.renderer.writeText(
                    row,
                    screen_col,
                    char_slice,
                    .default,
                    .default,
                    Attrs{},
                );
            } else {
                // Normal text
                self.renderer.writeText(
                    row,
                    screen_col,
                    char_slice,
                    .default,
                    .default,
                    Attrs{},
                );
            }

            screen_col += 1;
        }
    }
};

/// Run editor application
pub fn runEditor(allocator: std.mem.Allocator, filepath: ?[]const u8) !void {
    var app = try EditorApp.init(allocator);
    defer app.deinit();

    try app.run(filepath);
}
