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

/// Editor application
pub const EditorApp = struct {
    editor: Editor,
    renderer: Renderer,
    allocator: std.mem.Allocator,
    running: bool,
    gutter_config: gutter.GutterConfig,

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
        };
    }

    /// Clean up
    pub fn deinit(self: *EditorApp) void {
        self.editor.deinit();
        self.renderer.deinit();
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
                try self.handleMouseClick(mouse.row, mouse.col);
            },
            else => {},
        }
    }

    /// Handle mouse click - position cursor
    fn handleMouseClick(self: *EditorApp, screen_row: u16, screen_col: u16) !void {
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

        // Create position and update cursor
        const pos = Cursor.Position{
            .line = buffer_line,
            .col = buffer_col,
        };

        try self.editor.selections.setSingleCursor(self.allocator, pos);

        // If in visual mode, return to normal mode
        if (self.editor.getMode() == .select) {
            try self.editor.enterNormalMode();
        }
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

    /// Render cursor at current position
    fn renderCursor(self: *EditorApp, visible_lines: usize) !void {
        const buffer = self.editor.getActiveBuffer() orelse return;
        const cursor_pos = self.editor.getCursorPosition();
        const viewport = self.editor.getViewport(visible_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Check if cursor is in viewport
        if (cursor_pos.line < viewport.start_line or cursor_pos.line >= viewport.end_line) {
            return; // Cursor is off-screen
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

            // Check if this line has selection
            const line_has_selection = if (sel_range) |range|
                (line_num >= range.start.line and line_num <= range.end.line)
            else
                false;

            if (line_has_selection and sel_range != null) {
                // Render line character by character with selection highlighting
                try self.renderLineWithSelection(
                    row,
                    gutter_width,
                    line_text,
                    line_num,
                    sel_range.?,
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

    /// Render a line with selection highlighting
    fn renderLineWithSelection(
        self: *EditorApp,
        row: u16,
        start_col: u16,
        line_text: []const u8,
        line_num: usize,
        sel_range: anytype,
    ) !void {
        var col: usize = 0;
        var screen_col = start_col;

        while (col < line_text.len) : (col += 1) {
            // Determine if this character is in selection
            const is_selected = blk: {
                // Check if on selection start line
                if (line_num == sel_range.start.line and line_num == sel_range.end.line) {
                    // Single line selection
                    break :blk col >= sel_range.start.col and col < sel_range.end.col;
                } else if (line_num == sel_range.start.line) {
                    // Start of multi-line selection
                    break :blk col >= sel_range.start.col;
                } else if (line_num == sel_range.end.line) {
                    // End of multi-line selection
                    break :blk col < sel_range.end.col;
                } else if (line_num > sel_range.start.line and line_num < sel_range.end.line) {
                    // Middle of multi-line selection
                    break :blk true;
                } else {
                    break :blk false;
                }
            };

            const char_slice = line_text[col .. col + 1];
            const attrs = if (is_selected)
                Attrs{ .reverse = true }
            else
                Attrs{};

            self.renderer.writeText(
                row,
                screen_col,
                char_slice,
                .default,
                .default,
                attrs,
            );

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
