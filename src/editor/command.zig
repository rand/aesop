//! Command registry and execution system
//! Composable commands for modal editing

const std = @import("std");

// Forward declare Editor to avoid circular dependency
pub const Editor = @import("editor.zig").Editor;

/// Command context - passed to command handlers
pub const Context = struct {
    editor: *Editor,
};

/// Helper: Apply motion result based on current mode
/// In visual/select mode: extend selection
/// In normal mode: collapse to cursor
fn applyMotion(ctx: *Context, new_sel: Cursor.Selection) Result {
    if (ctx.editor.getMode() == .select) {
        // Visual mode: keep selection extended
        ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
            return Result.err("Failed to update selection");
        };
    } else {
        // Normal mode: collapse to cursor
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
            return Result.err("Failed to update cursor");
        };
    }
    return Result.ok();
}

/// Command result
pub const Result = union(enum) {
    success: void,
    error_msg: []const u8,

    pub fn ok() Result {
        return .{ .success = {} };
    }

    pub fn err(msg: []const u8) Result {
        return .{ .error_msg = msg };
    }
};

/// Command handler function type
pub const Handler = *const fn (ctx: *Context) Result;

/// Command metadata
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    handler: Handler,
    category: Category,

    pub const Category = enum {
        motion,      // Cursor movement
        edit,        // Text editing
        selection,   // Selection manipulation
        buffer,      // Buffer operations
        mode,        // Mode changes
        file,        // File I/O
        search,      // Search/replace
        view,        // Viewport control
        system,      // System commands
    };
};

/// Command registry
pub const Registry = struct {
    commands: std.StringHashMap(Command),
    allocator: std.mem.Allocator,

    /// Initialize empty registry
    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .commands = std.StringHashMap(Command).init(allocator),
            .allocator = allocator,
        };
    }

    /// Clean up registry
    pub fn deinit(self: *Registry) void {
        self.commands.deinit();
    }

    /// Register a command
    pub fn register(self: *Registry, cmd: Command) !void {
        try self.commands.put(cmd.name, cmd);
    }

    /// Get command by name
    pub fn get(self: *const Registry, name: []const u8) ?Command {
        return self.commands.get(name);
    }

    /// Execute command by name
    pub fn execute(self: *const Registry, name: []const u8, ctx: *Context) Result {
        if (self.get(name)) |cmd| {
            return cmd.handler(ctx);
        }
        return Result.err("Command not found");
    }

    /// Get all command names
    pub fn listCommands(self: *const Registry, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(allocator);
        defer names.deinit();

        var iter = self.commands.keyIterator();
        while (iter.next()) |key| {
            try names.append(key.*);
        }

        return names.toOwnedSlice();
    }

    /// Get commands by category
    pub fn getByCategory(self: *const Registry, allocator: std.mem.Allocator, category: Command.Category) ![]Command {
        var cmds = std.ArrayList(Command).init(allocator);
        defer cmds.deinit();

        var iter = self.commands.valueIterator();
        while (iter.next()) |cmd| {
            if (cmd.category == category) {
                try cmds.append(cmd.*);
            }
        }

        return cmds.toOwnedSlice();
    }

    /// Get command count
    pub fn count(self: *const Registry) usize {
        return self.commands.count();
    }
};

// === Built-in command handlers ===

const Motions = @import("motions.zig");
const Actions = @import("actions.zig");
const Cursor = @import("cursor.zig");
const Buffer = @import("../buffer/manager.zig");

fn moveLeft(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveLeft(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveRight(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveRight(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveUp(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveUp(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveDown(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveDown(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveWordForward(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveWordForward(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveWordBackward(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveWordBackward(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveWordEnd(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveWordEnd(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveLineStart(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveLineStart(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveLineEnd(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveLineEnd(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveFileStart(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveFileStart(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn moveFileEnd(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
    const new_sel = Motions.moveFileEnd(primary_sel, buffer);
    return applyMotion(ctx, new_sel);
}

fn insertMode(ctx: *Context) Result {
    ctx.editor.enterInsertMode() catch return Result.err("Failed to enter insert mode");
    return Result.ok();
}

fn insertAfter(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    // Move cursor right, then enter insert mode
    const new_sel = Motions.moveRight(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update cursor");
    ctx.editor.enterInsertMode() catch return Result.err("Failed to enter insert mode");
    return Result.ok();
}

fn insertLineStart(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    // Move to line start, then enter insert mode
    const new_sel = Motions.moveLineStart(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update cursor");
    ctx.editor.enterInsertMode() catch return Result.err("Failed to enter insert mode");
    return Result.ok();
}

fn insertLineEnd(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    // Move to line end, then enter insert mode
    const new_sel = Motions.moveLineEnd(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update cursor");
    ctx.editor.enterInsertMode() catch return Result.err("Failed to enter insert mode");
    return Result.ok();
}

fn openBelow(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        // Move to end of line, insert newline, enter insert mode
        const line_end_sel = Motions.moveLineEnd(primary_sel, buffer);
        const new_sel = Actions.insertNewline(buffer, line_end_sel) catch return Result.err("Failed to insert newline");

        buffer.metadata.markModified();
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update cursor");
        ctx.editor.enterInsertMode() catch return Result.err("Failed to enter insert mode");
        return Result.ok();
    }
    return Result.err("No active buffer");
}

fn openAbove(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        // Move to start of line, insert newline before current line, enter insert mode
        const line_start_sel = Motions.moveLineStart(primary_sel, buffer);
        _ = Actions.insertText(buffer, line_start_sel, "\n") catch return Result.err("Failed to insert newline");

        // Position stays at start of new line (where we just were)
        buffer.metadata.markModified();
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, line_start_sel.head) catch return Result.err("Failed to update cursor");
        ctx.editor.enterInsertMode() catch return Result.err("Failed to enter insert mode");
        return Result.ok();
    }
    return Result.err("No active buffer");
}

fn normalMode(ctx: *Context) Result {
    ctx.editor.enterNormalMode() catch return Result.err("Failed to enter normal mode");
    return Result.ok();
}

fn selectMode(ctx: *Context) Result {
    ctx.editor.enterSelectMode() catch return Result.err("Failed to enter select mode");
    return Result.ok();
}

// === Deletion commands ===

fn deleteCharAtCursor(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.deleteChar(buffer, primary_sel) catch return Result.err("Failed to delete character");
        buffer.metadata.markModified();
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update cursor");
        return Result.ok();
    }
    return Result.err("No active buffer");
}

fn deleteCharBeforeCursor(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.deleteCharBefore(buffer, primary_sel) catch return Result.err("Failed to delete character");
        buffer.metadata.markModified();
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update cursor");
        return Result.ok();
    }
    return Result.err("No active buffer");
}

fn deleteLine(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        // Move to line start, select entire line (including newline), delete
        const line_start = Motions.moveLineStart(primary_sel, buffer);
        const line_end = Motions.moveLineEnd(line_start, buffer);

        // Create selection from start to end of line
        const line_selection = Cursor.Selection.init(line_start.head, line_end.head);

        // Delete the selection (TODO: should yank to clipboard)
        const new_sel = Actions.deleteSelection(buffer, line_selection, null) catch return Result.err("Failed to delete line");
        buffer.metadata.markModified();
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update cursor");
        return Result.ok();
    }
    return Result.err("No active buffer");
}

fn deleteWord(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        // Get end of word
        const word_end = Motions.moveWordEnd(primary_sel, buffer);

        // Create selection from cursor to end of word
        const word_selection = Cursor.Selection.init(primary_sel.head, word_end.head);

        // Delete the selection (TODO: should yank to clipboard)
        const new_sel = Actions.deleteSelection(buffer, word_selection, null) catch return Result.err("Failed to delete word");
        buffer.metadata.markModified();
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update cursor");
        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Yank (copy) current line
fn yankLine(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    // Create selection spanning the entire line
    const line_start = Motions.moveLineStart(primary_sel, buffer);
    const line_end = Motions.moveLineEnd(line_start, buffer);
    const line_selection = Cursor.Selection.init(line_start.head, line_end.head);

    // Yank to clipboard
    Actions.yankSelection(buffer, line_selection, &ctx.editor.clipboard) catch {
        return Result.err("Failed to yank line");
    };

    // Show message
    ctx.editor.messages.add("Yanked line", .success) catch {};

    return Result.ok();
}

/// Paste clipboard content after cursor
fn pasteAfter(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    // Check clipboard has content
    if (ctx.editor.clipboard.getContent() == null) {
        return Result.err("Clipboard is empty");
    }

    // Paste using Actions
    const new_sel = Actions.pasteAfter(buffer, primary_sel, &ctx.editor.clipboard) catch {
        return Result.err("Failed to paste");
    };

    // Update cursor
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
        return Result.err("Failed to update cursor");
    };

    buffer.metadata.markModified();

    // Show message
    ctx.editor.messages.add("Pasted after cursor", .success) catch {};

    return Result.ok();
}

/// Paste clipboard content before cursor
fn pasteBefore(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    // Check clipboard has content
    if (ctx.editor.clipboard.getContent() == null) {
        return Result.err("Clipboard is empty");
    }

    // Paste using Actions
    const new_sel = Actions.pasteBefore(buffer, primary_sel, &ctx.editor.clipboard) catch {
        return Result.err("Failed to paste");
    };

    // Update cursor
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
        return Result.err("Failed to update cursor");
    };

    buffer.metadata.markModified();

    // Show message
    ctx.editor.messages.add("Pasted before cursor", .success) catch {};

    return Result.ok();
}

/// Delete selection (visual mode)
fn deleteSelection(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    // Only works on non-collapsed selections
    if (primary_sel.isCollapsed()) {
        return Result.err("No selection to delete");
    }

    // Delete and yank to clipboard
    const new_sel = Actions.deleteSelection(buffer, primary_sel, &ctx.editor.clipboard) catch {
        return Result.err("Failed to delete selection");
    };

    // Update cursor and mark modified
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
        return Result.err("Failed to update cursor");
    };
    buffer.metadata.markModified();

    // Return to normal mode
    ctx.editor.enterNormalMode() catch {};

    // Show message
    ctx.editor.messages.add("Deleted selection", .success) catch {};

    return Result.ok();
}

/// Yank selection (visual mode)
fn yankSelection(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    // Only works on non-collapsed selections
    if (primary_sel.isCollapsed()) {
        return Result.err("No selection to yank");
    }

    // Yank to clipboard
    Actions.yankSelection(buffer, primary_sel, &ctx.editor.clipboard) catch {
        return Result.err("Failed to yank selection");
    };

    // Return to normal mode
    ctx.editor.enterNormalMode() catch {};

    // Show message
    ctx.editor.messages.add("Yanked selection", .success) catch {};

    return Result.ok();
}

/// Undo last operation
fn undo(ctx: *Context) Result {
    if (!ctx.editor.undo_history.canUndo()) {
        return Result.err("Nothing to undo");
    }

    // Get undo group
    const group = ctx.editor.undo_history.getUndo() orelse {
        return Result.err("Undo failed");
    };

    // TODO: Apply undo operations to buffer
    // For now, just restore cursor position
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, group.cursor_before) catch {
        return Result.err("Failed to restore cursor");
    };

    // Show message
    ctx.editor.messages.add("Undo applied", .info) catch {};

    return Result.ok();
}

/// Save current buffer
fn saveBuffer(ctx: *Context) Result {
    ctx.editor.save() catch |err| {
        const msg = switch (err) {
            error.NoActiveBuffer => "No active buffer to save",
            error.NoFilepath => "No file path (use save_as)",
            else => "Failed to save file",
        };
        return Result.err(msg);
    };

    ctx.editor.messages.add("File saved", .success) catch {};
    return Result.ok();
}

/// Write buffer (alias for save)
fn writeBuffer(ctx: *Context) Result {
    return saveBuffer(ctx);
}

/// Toggle command palette
fn togglePalette(ctx: *Context) Result {
    if (ctx.editor.palette.visible) {
        ctx.editor.palette.hide();
    } else {
        ctx.editor.palette.show();
    }
    return Result.ok();
}

/// Find next occurrence of search query
fn findNext(ctx: *Context) Result {
    if (!ctx.editor.search.active) {
        return Result.err("No active search");
    }

    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer ctx.editor.allocator.free(text);

    const cursor_pos = ctx.editor.getCursorPosition();

    // Search from next position
    const search_start = Cursor.Position{
        .line = cursor_pos.line,
        .col = cursor_pos.col + 1,
    };

    if (ctx.editor.search.findNext(text, search_start)) |match| {
        // Move cursor to match start
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, match.start) catch {
            return Result.err("Failed to update cursor");
        };
        ctx.editor.ensureCursorVisible();
        return Result.ok();
    } else {
        // Wrap around to beginning
        if (ctx.editor.search.findNext(text, .{ .line = 0, .col = 0 })) |match| {
            ctx.editor.selections.setSingleCursor(ctx.editor.allocator, match.start) catch {
                return Result.err("Failed to update cursor");
            };
            ctx.editor.ensureCursorVisible();
            ctx.editor.messages.add("Search wrapped", .info) catch {};
            return Result.ok();
        }
        return Result.err("No match found");
    }
}

/// Find previous occurrence of search query
fn findPrevious(ctx: *Context) Result {
    if (!ctx.editor.search.active) {
        return Result.err("No active search");
    }

    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer ctx.editor.allocator.free(text);

    const cursor_pos = ctx.editor.getCursorPosition();

    if (ctx.editor.search.findPrevious(text, cursor_pos)) |match| {
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, match.start) catch {
            return Result.err("Failed to update cursor");
        };
        ctx.editor.ensureCursorVisible();
        return Result.ok();
    } else {
        return Result.err("No previous match");
    }
}

/// Redo last undone operation
fn redo(ctx: *Context) Result {
    if (!ctx.editor.undo_history.canRedo()) {
        return Result.err("Nothing to redo");
    }

    // Get redo group
    const group = ctx.editor.undo_history.getRedo() orelse {
        return Result.err("Redo failed");
    };

    // TODO: Apply redo operations to buffer
    // For now, just restore cursor position
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, group.cursor_after) catch {
        return Result.err("Failed to restore cursor");
    };

    // Show message
    ctx.editor.messages.add("Redo applied", .info) catch {};

    return Result.ok();
}

/// Register all built-in commands
pub fn registerBuiltins(registry: *Registry) !void {
    // Motion commands - basic
    try registry.register(.{
        .name = "move_left",
        .description = "Move cursor left",
        .handler = moveLeft,
        .category = .motion,
    });

    try registry.register(.{
        .name = "move_right",
        .description = "Move cursor right",
        .handler = moveRight,
        .category = .motion,
    });

    try registry.register(.{
        .name = "move_up",
        .description = "Move cursor up",
        .handler = moveUp,
        .category = .motion,
    });

    try registry.register(.{
        .name = "move_down",
        .description = "Move cursor down",
        .handler = moveDown,
        .category = .motion,
    });

    // Motion commands - word
    try registry.register(.{
        .name = "move_word_forward",
        .description = "Move to start of next word",
        .handler = moveWordForward,
        .category = .motion,
    });

    try registry.register(.{
        .name = "move_word_backward",
        .description = "Move to start of previous word",
        .handler = moveWordBackward,
        .category = .motion,
    });

    try registry.register(.{
        .name = "move_word_end",
        .description = "Move to end of word",
        .handler = moveWordEnd,
        .category = .motion,
    });

    // Motion commands - line
    try registry.register(.{
        .name = "move_line_start",
        .description = "Move to start of line",
        .handler = moveLineStart,
        .category = .motion,
    });

    try registry.register(.{
        .name = "move_line_end",
        .description = "Move to end of line",
        .handler = moveLineEnd,
        .category = .motion,
    });

    // Motion commands - file
    try registry.register(.{
        .name = "move_file_start",
        .description = "Move to start of file",
        .handler = moveFileStart,
        .category = .motion,
    });

    try registry.register(.{
        .name = "move_file_end",
        .description = "Move to end of file",
        .handler = moveFileEnd,
        .category = .motion,
    });

    // Mode commands
    try registry.register(.{
        .name = "insert_mode",
        .description = "Enter insert mode",
        .handler = insertMode,
        .category = .mode,
    });

    try registry.register(.{
        .name = "insert_after",
        .description = "Move cursor right and enter insert mode (a)",
        .handler = insertAfter,
        .category = .mode,
    });

    try registry.register(.{
        .name = "insert_line_start",
        .description = "Move to line start and enter insert mode (I)",
        .handler = insertLineStart,
        .category = .mode,
    });

    try registry.register(.{
        .name = "insert_line_end",
        .description = "Move to line end and enter insert mode (A)",
        .handler = insertLineEnd,
        .category = .mode,
    });

    try registry.register(.{
        .name = "open_below",
        .description = "Open new line below and enter insert mode (o)",
        .handler = openBelow,
        .category = .mode,
    });

    try registry.register(.{
        .name = "open_above",
        .description = "Open new line above and enter insert mode (O)",
        .handler = openAbove,
        .category = .mode,
    });

    try registry.register(.{
        .name = "normal_mode",
        .description = "Enter normal mode",
        .handler = normalMode,
        .category = .mode,
    });

    try registry.register(.{
        .name = "select_mode",
        .description = "Enter select mode",
        .handler = selectMode,
        .category = .mode,
    });

    // Deletion commands
    try registry.register(.{
        .name = "delete_char",
        .description = "Delete character at cursor (x)",
        .handler = deleteCharAtCursor,
        .category = .edit,
    });

    try registry.register(.{
        .name = "delete_char_before",
        .description = "Delete character before cursor (X)",
        .handler = deleteCharBeforeCursor,
        .category = .edit,
    });

    try registry.register(.{
        .name = "delete_line",
        .description = "Delete current line (dd)",
        .handler = deleteLine,
        .category = .edit,
    });

    try registry.register(.{
        .name = "delete_word",
        .description = "Delete word from cursor (dw)",
        .handler = deleteWord,
        .category = .edit,
    });

    // Undo/redo commands
    try registry.register(.{
        .name = "undo",
        .description = "Undo last operation (u)",
        .handler = undo,
        .category = .edit,
    });

    try registry.register(.{
        .name = "redo",
        .description = "Redo last undone operation (U)",
        .handler = redo,
        .category = .edit,
    });

    // Clipboard commands
    try registry.register(.{
        .name = "yank_line",
        .description = "Yank (copy) current line (yy)",
        .handler = yankLine,
        .category = .edit,
    });

    try registry.register(.{
        .name = "paste_after",
        .description = "Paste after cursor (p)",
        .handler = pasteAfter,
        .category = .edit,
    });

    try registry.register(.{
        .name = "paste_before",
        .description = "Paste before cursor (P)",
        .handler = pasteBefore,
        .category = .edit,
    });

    // Visual mode operations
    try registry.register(.{
        .name = "delete_selection",
        .description = "Delete visual selection (d in visual)",
        .handler = deleteSelection,
        .category = .edit,
    });

    try registry.register(.{
        .name = "yank_selection",
        .description = "Yank visual selection (y in visual)",
        .handler = yankSelection,
        .category = .edit,
    });

    // Command palette
    try registry.register(.{
        .name = "toggle_palette",
        .description = "Toggle command palette (Space P)",
        .handler = togglePalette,
        .category = .system,
    });

    // File operations
    try registry.register(.{
        .name = "save",
        .description = "Save current buffer (Space W)",
        .handler = saveBuffer,
        .category = .file,
    });

    try registry.register(.{
        .name = "write",
        .description = "Write current buffer (alias for save)",
        .handler = writeBuffer,
        .category = .file,
    });

    // Search operations
    try registry.register(.{
        .name = "find_next",
        .description = "Find next occurrence (n)",
        .handler = findNext,
        .category = .search,
    });

    try registry.register(.{
        .name = "find_previous",
        .description = "Find previous occurrence (N)",
        .handler = findPrevious,
        .category = .search,
    });
}

test "registry: init and register" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    const cmd = Command{
        .name = "test_command",
        .description = "Test command",
        .handler = moveLeft,
        .category = .motion,
    };

    try registry.register(cmd);
    try std.testing.expectEqual(@as(usize, 1), registry.count());

    const retrieved = registry.get("test_command").?;
    try std.testing.expectEqualStrings("test_command", retrieved.name);
}

test "registry: execute command" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registerBuiltins(&registry);

    var ctx = Context{};
    const result = registry.execute("move_left", &ctx);

    try std.testing.expectEqual(@as(std.meta.Tag(Result), .success), std.meta.activeTag(result));
}

test "registry: get by category" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registerBuiltins(&registry);

    const motions = try registry.getByCategory(allocator, .motion);
    defer allocator.free(motions);

    try std.testing.expect(motions.len > 0);
}

test "registry: list commands" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registerBuiltins(&registry);

    const names = try registry.listCommands(allocator);
    defer allocator.free(names);

    try std.testing.expect(names.len > 0);
}
