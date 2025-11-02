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

    // Viewport
    scroll_offset: usize, // Line offset for scrolling

    /// Initialize editor
    pub fn init(allocator: std.mem.Allocator) !Editor {
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
        _ = try self.buffer_manager.openFile(filepath);
        // Reset selections for new buffer
        try self.selections.setSingleCursor(self.allocator, .{ .line = 0, .col = 0 });
        self.scroll_offset = 0;
    }

    /// Save active buffer
    pub fn save(self: *Editor) !void {
        if (self.getActiveBuffer()) |buffer| {
            try buffer.save();
        } else {
            return error.NoActiveBuffer;
        }
    }

    /// Save active buffer as...
    pub fn saveAs(self: *Editor, filepath: []const u8) !void {
        if (self.getActiveBuffer()) |buffer| {
            try buffer.saveAs(filepath);
        } else {
            return error.NoActiveBuffer;
        }
    }

    /// Process key input
    pub fn processKey(self: *Editor, key: Keymap.Key) !void {
        const mode = self.getMode();

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
        } else if (mode.acceptsTextInput()) {
            // Handle text input in insert/command mode
            try self.handleTextInput(key);
        }
    }

    /// Handle text input (characters, newlines, backspace, tab)
    fn handleTextInput(self: *Editor, key: Keymap.Key) !void {
        // Get mutable buffer reference for text modification
        if (self.buffer_manager.active_buffer_id) |id| {
            const buffer = self.buffer_manager.getBufferMut(id) orelse return error.NoActiveBuffer;

            // Get primary selection
            const primary_sel = self.selections.primary(self.allocator) orelse return error.NoSelection;

            // Handle different key types
            switch (key) {
                .char => |codepoint| {
                    // Convert character to UTF-8 bytes
                    var buf: [4]u8 = undefined;
                    const len = try std.unicode.utf8Encode(codepoint, &buf);
                    const text = buf[0..len];

                    // Insert the character
                    const new_sel = try Actions.insertText(buffer, primary_sel, text);

                    // Update selection
                    try self.selections.setSingleCursor(self.allocator, new_sel.head);

                    // Mark buffer as modified
                    buffer.metadata.markModified();
                },
                .special => |special_key| {
                    switch (special_key) {
                        .enter => {
                            // Insert newline
                            const new_sel = try Actions.insertNewline(buffer, primary_sel);
                            try self.selections.setSingleCursor(self.allocator, new_sel.head);
                            buffer.metadata.markModified();
                        },
                        .backspace => {
                            // Delete character before cursor
                            const new_sel = try Actions.deleteCharBefore(buffer, primary_sel);
                            try self.selections.setSingleCursor(self.allocator, new_sel.head);
                            buffer.metadata.markModified();
                        },
                        .tab => {
                            // Insert tab (TODO: make spaces configurable)
                            const tab_text = "    "; // 4 spaces default
                            const new_sel = try Actions.insertText(buffer, primary_sel, tab_text);
                            try self.selections.setSingleCursor(self.allocator, new_sel.head);
                            buffer.metadata.markModified();
                        },
                        else => {
                            // Ignore other special keys in insert mode
                        },
                    }
                },
            }
        }
    }

    /// Handle mode transitions
    pub fn enterNormalMode(self: *Editor) !void {
        try self.mode_manager.enterNormal();
        self.keymap_manager.clearPending();
    }

    pub fn enterInsertMode(self: *Editor) !void {
        try self.mode_manager.enterInsert();
        self.keymap_manager.clearPending();
    }

    pub fn enterSelectMode(self: *Editor) !void {
        try self.mode_manager.enterSelect();
        self.keymap_manager.clearPending();
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
