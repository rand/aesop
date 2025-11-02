//! Main editor state coordinator
//! Ties together buffers, selections, modes, commands, and rendering

const std = @import("std");
const Mode = @import("mode.zig");
const Cursor = @import("cursor.zig");
const Buffer = @import("../buffer/manager.zig");
const Command = @import("command.zig");
const Keymap = @import("keymap.zig");
const Motions = @import("motions.zig");
const Actions = @import("actions.zig");
const Message = @import("message.zig");
const Undo = @import("undo.zig");
const Palette = @import("palette.zig");
const Search = @import("search.zig");
const Config = @import("config.zig");
const Window = @import("window.zig");
const FileFinder = @import("file_finder.zig");
const PluginSystem = @import("../plugin/system.zig");
const Renderer = @import("../render/renderer.zig").Renderer;

/// Editor state - the main coordinator
pub const Editor = struct {
    allocator: std.mem.Allocator,

    // Core state
    mode_manager: Mode.ModeManager,
    buffer_manager: Buffer.BufferManager,
    selections: Cursor.SelectionSet,
    command_registry: Command.Registry,
    keymap_manager: Keymap.KeymapManager,
    clipboard: Actions.Clipboard,
    messages: Message.MessageQueue,
    undo_history: Undo.UndoHistory,
    palette: Palette.Palette,
    search: Search.Search,
    config: Config.Config,
    window_manager: Window.WindowManager,
    plugin_manager: PluginSystem.PluginManager,
    file_finder: FileFinder.FileFinder,

    // Viewport (legacy - will be replaced by window_manager)
    scroll_offset: usize, // Line offset for scrolling

    /// Initialize editor
    pub fn init(allocator: std.mem.Allocator) !Editor {
        // Initialize window manager with default terminal dimensions
        const initial_dims = Window.Dimensions{
            .row = 0,
            .col = 0,
            .height = 24,
            .width = 80,
        };

        var editor = Editor{
            .allocator = allocator,
            .mode_manager = Mode.ModeManager.init(),
            .buffer_manager = Buffer.BufferManager.init(allocator),
            .selections = try Cursor.SelectionSet.initWithCursor(allocator, .{ .line = 0, .col = 0 }),
            .command_registry = Command.Registry.init(allocator),
            .keymap_manager = Keymap.KeymapManager.init(allocator),
            .clipboard = Actions.Clipboard.init(allocator),
            .messages = Message.MessageQueue.init(allocator),
            .undo_history = Undo.UndoHistory.init(allocator),
            .palette = Palette.Palette.init(allocator),
            .search = Search.Search.init(allocator),
            .config = Config.Config.init(allocator),
            .window_manager = try Window.WindowManager.init(allocator, initial_dims),
            .plugin_manager = PluginSystem.PluginManager.init(allocator),
            .file_finder = FileFinder.FileFinder.init(allocator),
            .scroll_offset = 0,
        };

        // Register built-in commands
        try Command.registerBuiltins(&editor.command_registry);

        // Setup default keymaps
        try Keymap.setupDefaults(&editor.keymap_manager);

        return editor;
    }

    /// Clean up editor
    pub fn deinit(self: *Editor) void {
        self.file_finder.deinit();
        self.plugin_manager.deinit();
        self.window_manager.deinit();
        self.config.deinit();
        self.search.deinit();
        self.palette.deinit();
        self.undo_history.deinit();
        self.messages.deinit();
        self.clipboard.deinit();
        self.selections.deinit(self.allocator);
        self.buffer_manager.deinit();
        self.command_registry.deinit();
        self.keymap_manager.deinit();
    }

    /// Get current mode
    pub fn getMode(self: *const Editor) Mode.Mode {
        return self.mode_manager.getMode();
    }

    /// Get active buffer
    pub fn getActiveBuffer(self: *const Editor) ?*const Buffer.Buffer {
        return self.buffer_manager.getActiveBuffer();
    }

    /// Create new empty buffer
    pub fn newBuffer(self: *Editor) !void {
        _ = try self.buffer_manager.createEmpty();
        // Reset selections for new buffer
        try self.selections.setSingleCursor(self.allocator, .{ .line = 0, .col = 0 });
        self.scroll_offset = 0;
    }

    /// Open file
    pub fn openFile(self: *Editor, filepath: []const u8) !void {
        const buffer_id = try self.buffer_manager.openFile(filepath);
        // Reset selections for new buffer
        try self.selections.setSingleCursor(self.allocator, .{ .line = 0, .col = 0 });
        self.scroll_offset = 0;

        // Dispatch buffer open event to plugins
        self.plugin_manager.dispatchBufferOpen(buffer_id) catch {};
    }

    /// Save active buffer
    pub fn save(self: *Editor) !void {
        if (self.buffer_manager.active_buffer_id) |id| {
            const buffer = self.buffer_manager.getBufferMut(id) orelse return error.NoActiveBuffer;
            try buffer.save();

            // Dispatch buffer save event to plugins
            self.plugin_manager.dispatchBufferSave(id) catch {};
        } else {
            return error.NoActiveBuffer;
        }
    }

    /// Save active buffer as...
    pub fn saveAs(self: *Editor, filepath: []const u8) !void {
        if (self.buffer_manager.active_buffer_id) |id| {
            const buffer = self.buffer_manager.getBufferMut(id) orelse return error.NoActiveBuffer;
            try buffer.saveAs(filepath);
        } else {
            return error.NoActiveBuffer;
        }
    }

    /// Process key input
    pub fn processKey(self: *Editor, key: Keymap.Key) !void {
        const mode = self.getMode();

        // Special handling for incremental search
        if (self.search.incremental) {
            try self.handleSearchInput(key);
            return;
        }

        // Try to match key to command
        if (try self.keymap_manager.processKey(mode, key)) |command_name| {
            // Execute command with editor context
            var ctx = Command.Context{ .editor = self };
            const result = self.command_registry.execute(command_name, &ctx);

            switch (result) {
                .success => {},
                .error_msg => |msg| {
                    // Show error in message queue
                    self.messages.add(msg, .error_msg) catch {};
                },
            }

            // Auto-scroll viewport to follow cursor
            self.ensureCursorVisible();
        } else if (mode.acceptsTextInput()) {
            // Handle text input in insert/command mode
            try self.handleTextInput(key);

            // Auto-scroll viewport to follow cursor
            self.ensureCursorVisible();
        }
    }

    /// Handle input during incremental search
    fn handleSearchInput(self: *Editor, key: Keymap.Key) !void {
        switch (key) {
            .char => |c| {
                // Add character to search query
                const char_byte = @as(u8, @intCast(c));
                try self.search.appendChar(char_byte);

                // Update message with current query
                const query = self.search.getQuery();
                const msg = try std.fmt.allocPrint(self.allocator, "Search: {s}", .{query});
                defer self.allocator.free(msg);
                self.messages.add(msg, .info) catch {};

                // Find first match and jump to it
                if (self.buffer_manager.active_buffer_id) |id| {
                    const buffer = self.buffer_manager.getBuffer(id) orelse return;
                    const text = try buffer.getText();
                    defer self.allocator.free(text);

                    const cursor_pos = self.getCursorPosition();
                    if (self.search.findNext(text, cursor_pos)) |match| {
                        try self.selections.setSingleCursor(self.allocator, match.start);
                        self.ensureCursorVisible();
                    }
                }
            },
            .special => |special| {
                switch (special) {
                    .backspace => {
                        self.search.backspace();
                        const query = self.search.getQuery();
                        const msg = try std.fmt.allocPrint(self.allocator, "Search: {s}", .{query});
                        defer self.allocator.free(msg);
                        self.messages.add(msg, .info) catch {};
                    },
                    .enter => {
                        // Accept search and exit incremental mode
                        self.search.incremental = false;
                        self.messages.clear();
                    },
                    .escape => {
                        // Cancel search
                        self.search.clear();
                        self.messages.clear();
                    },
                    else => {},
                }
            },
        }
    }

    /// Ensure cursor is visible in viewport (auto-scroll)
    pub fn ensureCursorVisible(self: *Editor) void {
        const cursor_pos = self.getCursorPosition();
        const buffer = self.getActiveBuffer() orelse return;
        const total_lines = buffer.lineCount();

        // Assume standard terminal height for now (will be passed from renderer later)
        const viewport_height: usize = 24;
        const visible_lines = viewport_height -| 2; // Reserve for status

        // Calculate desired viewport bounds
        const viewport_end = self.scroll_offset + visible_lines;

        // Scroll down if cursor is below viewport
        if (cursor_pos.line >= viewport_end) {
            self.scroll_offset = cursor_pos.line -| (visible_lines - 1);
        }

        // Scroll up if cursor is above viewport
        if (cursor_pos.line < self.scroll_offset) {
            self.scroll_offset = cursor_pos.line;
        }

        // Clamp to valid range
        const max_scroll = if (total_lines > visible_lines) total_lines - visible_lines else 0;
        self.scroll_offset = @min(self.scroll_offset, max_scroll);
    }

    /// Handle text input (characters, newlines, backspace, tab)
    fn handleTextInput(self: *Editor, key: Keymap.Key) !void {
        // Get mutable buffer reference for text modification
        if (self.buffer_manager.active_buffer_id) |id| {
            const buffer = self.buffer_manager.getBufferMut(id) orelse return error.NoActiveBuffer;

            // Get all selections
            const all_selections = self.selections.all(self.allocator);

            // Determine text to insert
            const text_to_insert: ?[]const u8 = switch (key) {
                .char => |codepoint| blk: {
                    // Convert character to UTF-8 bytes
                    var buf: [4]u8 = undefined;
                    const len = try std.unicode.utf8Encode(codepoint, &buf);
                    // Allocate persistent storage for the character
                    const persistent = try self.allocator.alloc(u8, len);
                    @memcpy(persistent, buf[0..len]);
                    break :blk persistent;
                },
                .special => |special_key| switch (special_key) {
                    .enter => "\n",
                    .tab => "    ", // 4 spaces default
                    else => null,
                },
            };
            defer if (text_to_insert) |txt| {
                // Free if we allocated
                if (key == .char) {
                    self.allocator.free(txt);
                }
            };

            // Apply operation to all cursors (in reverse order to maintain positions)
            var new_selections = std.ArrayList(Cursor.Selection).empty;
            defer new_selections.deinit(self.allocator);

            var i: usize = all_selections.len;
            while (i > 0) {
                i -= 1;
                const sel = all_selections[i];

                const new_sel = blk: {
                    if (text_to_insert) |txt| {
                        break :blk try Actions.insertText(buffer, sel, txt);
                    } else if (key == .special) {
                        // Handle backspace specially
                        if (key.special == .backspace) {
                            break :blk try Actions.deleteCharBefore(buffer, sel);
                        }
                    }
                    break :blk sel;
                };

                // Prepend to maintain order
                try new_selections.insert(self.allocator, 0, new_sel);
            }

            // Update all selections
            self.selections.clear(self.allocator);
            for (new_selections.items) |sel| {
                try self.selections.add(self.allocator, sel);
            }
            self.selections.primary_index = if (new_selections.items.len > 0) new_selections.items.len - 1 else 0;

            // Mark buffer as modified
            buffer.metadata.markModified();
        }
    }

    /// Handle mode transitions
    pub fn enterNormalMode(self: *Editor) !void {
        const old_mode = self.mode_manager.getMode();
        try self.mode_manager.enterNormal();
        self.keymap_manager.clearPending();

        // Dispatch mode change to plugins
        self.plugin_manager.dispatchModeChange(@intFromEnum(old_mode), @intFromEnum(Mode.Mode.normal)) catch {};
    }

    pub fn enterInsertMode(self: *Editor) !void {
        const old_mode = self.mode_manager.getMode();
        try self.mode_manager.enterInsert();
        self.keymap_manager.clearPending();

        // Dispatch mode change to plugins
        self.plugin_manager.dispatchModeChange(@intFromEnum(old_mode), @intFromEnum(Mode.Mode.insert)) catch {};
    }

    pub fn enterSelectMode(self: *Editor) !void {
        const old_mode = self.mode_manager.getMode();
        try self.mode_manager.enterSelect();
        self.keymap_manager.clearPending();

        // Dispatch mode change to plugins
        self.plugin_manager.dispatchModeChange(@intFromEnum(old_mode), @intFromEnum(Mode.Mode.select)) catch {};
    }

    /// Get viewport info for rendering
    pub fn getViewport(self: *const Editor, screen_height: usize) struct {
        start_line: usize,
        end_line: usize,
    } {
        const buffer = self.buffer_manager.getActiveBuffer();
        const total_lines = if (buffer) |b| b.lineCount() else 0;

        const visible_lines = screen_height -| 2; // Reserve space for status line
        const end_line = @min(self.scroll_offset + visible_lines, total_lines);

        return .{
            .start_line = self.scroll_offset,
            .end_line = end_line,
        };
    }

    /// Scroll viewport
    pub fn scroll(self: *Editor, delta: isize) void {
        if (delta < 0) {
            const abs_delta: usize = @intCast(@abs(delta));
            self.scroll_offset -|= abs_delta;
        } else {
            self.scroll_offset += @intCast(delta);
        }
    }

    /// Get cursor position (primary selection head)
    pub fn getCursorPosition(self: *const Editor) Cursor.Position {
        if (self.selections.primary(self.allocator)) |sel| {
            return sel.head;
        }
        return .{ .line = 0, .col = 0 };
    }

    /// Get status line info
    pub fn getStatusInfo(self: *const Editor) StatusInfo {
        const buffer = self.buffer_manager.getActiveBuffer();
        const cursor_pos = self.getCursorPosition();

        return .{
            .mode = self.getMode(),
            .buffer_name = if (buffer) |b| b.metadata.getName() else "[No Name]",
            .modified = if (buffer) |b| b.metadata.modified else false,
            .readonly = if (buffer) |b| b.metadata.readonly else false,
            .line = cursor_pos.line + 1, // 1-indexed for display
            .col = cursor_pos.col + 1,
            .total_lines = if (buffer) |b| b.lineCount() else 0,
            .selection_count = self.selections.count(self.allocator),
            .can_undo = self.undo_history.canUndo(),
            .can_redo = self.undo_history.canRedo(),
        };
    }

    pub const StatusInfo = struct {
        mode: Mode.Mode,
        buffer_name: []const u8,
        modified: bool,
        readonly: bool,
        line: usize,
        col: usize,
        total_lines: usize,
        selection_count: usize,
        can_undo: bool,
        can_redo: bool,
    };
};

test "editor: init and deinit" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try std.testing.expectEqual(Mode.Mode.normal, editor.getMode());
}

test "editor: create buffer" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();
    try std.testing.expect(editor.getActiveBuffer() != null);
}

test "editor: mode transitions" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.enterInsertMode();
    try std.testing.expectEqual(Mode.Mode.insert, editor.getMode());

    try editor.enterNormalMode();
    try std.testing.expectEqual(Mode.Mode.normal, editor.getMode());
}

test "editor: get status info" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();

    const info = editor.getStatusInfo();
    try std.testing.expectEqual(Mode.Mode.normal, info.mode);
    try std.testing.expectEqual(@as(usize, 1), info.selection_count);
}
