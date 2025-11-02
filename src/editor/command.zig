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

/// Toggle file finder
fn toggleFileFinder(ctx: *Context) Result {
    if (ctx.editor.file_finder.visible) {
        ctx.editor.file_finder.hide();
    } else {
        ctx.editor.file_finder.show();
        // Scan current directory if cache not valid
        if (!ctx.editor.file_finder.cache_valid) {
            ctx.editor.file_finder.scanDirectory(".") catch {
                return Result.err("Failed to scan directory");
            };
        }
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

/// Add cursor on line above
fn addCursorAbove(ctx: *Context) Result {
    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    if (primary.head.line == 0) {
        return Result.err("Already at first line");
    }

    // Create new cursor one line above, same column
    const new_pos = Cursor.Position{
        .line = primary.head.line - 1,
        .col = primary.head.col,
    };

    // Add to selection set
    ctx.editor.selections.addCursor(ctx.editor.allocator, new_pos) catch {
        return Result.err("Failed to add cursor");
    };

    return Result.ok();
}

/// Add cursor on line below
fn addCursorBelow(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const total_lines = buffer.lineCount();
    if (primary.head.line + 1 >= total_lines) {
        return Result.err("Already at last line");
    }

    // Create new cursor one line below, same column
    const new_pos = Cursor.Position{
        .line = primary.head.line + 1,
        .col = primary.head.col,
    };

    // Add to selection set
    ctx.editor.selections.addCursor(ctx.editor.allocator, new_pos) catch {
        return Result.err("Failed to add cursor");
    };

    return Result.ok();
}

/// Clear all cursors except primary
fn clearExtraCursors(ctx: *Context) Result {
    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, primary.head) catch {
        return Result.err("Failed to clear cursors");
    };

    return Result.ok();
}

/// Start search with current selection as query
fn startSearch(ctx: *Context) Result {
    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    // If selection is not collapsed, use selected text as query
    if (!primary.isCollapsed()) {
        const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
            return Result.err("No active buffer");
        };

        const text = buffer.getText() catch {
            return Result.err("Failed to get buffer text");
        };
        defer ctx.editor.allocator.free(text);

        const range = primary.range();

        // Extract selected text (simplified - only works for single line)
        if (range.start.line == range.end.line) {
            // Calculate byte offset for start
            var offset: usize = 0;
            var line: usize = 0;
            var col: usize = 0;

            while (offset < text.len) {
                if (line == range.start.line and col == range.start.col) {
                    break;
                }
                if (text[offset] == '\n') {
                    line += 1;
                    col = 0;
                } else {
                    col += 1;
                }
                offset += 1;
            }

            const start_offset = offset;

            // Find end offset
            while (offset < text.len and col < range.end.col) {
                col += 1;
                offset += 1;
            }

            const selected_text = text[start_offset..offset];
            ctx.editor.search.setQuery(selected_text) catch {
                return Result.err("Query too long");
            };

            ctx.editor.messages.add("Search started", .info) catch {};
            return Result.ok();
        }
    }

    return Result.err("Select text to search");
}

/// Duplicate current line
fn duplicateLine(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };

    const cursor_pos = ctx.editor.getCursorPosition();
    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer ctx.editor.allocator.free(text);

    // Find current line bounds
    var line: usize = 0;
    var line_start: usize = 0;
    var offset: usize = 0;

    while (offset < text.len) {
        if (line == cursor_pos.line) {
            line_start = offset;
            break;
        }
        if (text[offset] == '\n') {
            line += 1;
        }
        offset += 1;
    }

    // Find line end
    var line_end = line_start;
    while (line_end < text.len and text[line_end] != '\n') {
        line_end += 1;
    }

    const line_text = text[line_start..line_end];

    // Build text with newline
    const dup_text = std.fmt.allocPrint(ctx.editor.allocator, "\n{s}", .{line_text}) catch {
        return Result.err("Failed to allocate");
    };
    defer ctx.editor.allocator.free(dup_text);

    // Insert at end of current line
    const end_of_line_pos = Cursor.Position{ .line = cursor_pos.line, .col = line_text.len };
    const end_sel = Cursor.Selection.cursor(end_of_line_pos);

    _ = Actions.insertText(buffer, end_sel, dup_text) catch {
        return Result.err("Failed to insert");
    };

    buffer.metadata.markModified();

    // Move cursor to duplicated line
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, .{ .line = cursor_pos.line + 1, .col = cursor_pos.col }) catch {};

    return Result.ok();
}

/// Join current line with next line
fn joinLines(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };

    const cursor_pos = ctx.editor.getCursorPosition();
    const total_lines = buffer.lineCount();

    if (cursor_pos.line + 1 >= total_lines) {
        return Result.err("No next line to join");
    }

    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer ctx.editor.allocator.free(text);

    // Find newline at end of current line
    var line: usize = 0;
    var offset: usize = 0;

    while (offset < text.len) {
        if (line == cursor_pos.line) {
            // Find the newline
            while (offset < text.len and text[offset] != '\n') {
                offset += 1;
            }
            if (offset < text.len) {
                // Delete the newline by deleting character from start of next line
                _ = Actions.deleteCharBefore(buffer, Cursor.Selection.cursor(.{ .line = cursor_pos.line + 1, .col = 0 })) catch {
                    return Result.err("Failed to delete newline");
                };

                buffer.metadata.markModified();
                return Result.ok();
            }
        }
        if (text[offset] == '\n') {
            line += 1;
        }
        offset += 1;
    }

    return Result.err("Failed to join lines");
}

/// Delete to end of line
fn deleteToEndOfLine(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };

    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer ctx.editor.allocator.free(text);

    // Find end of current line
    var line: usize = 0;
    var col: usize = 0;
    var offset: usize = 0;

    while (offset < text.len) {
        if (line == primary.head.line and col == primary.head.col) {
            break;
        }
        if (text[offset] == '\n') {
            line += 1;
            col = 0;
        } else {
            col += 1;
        }
        offset += 1;
    }

    // Find end of line
    var end_offset = offset;
    while (end_offset < text.len and text[end_offset] != '\n') {
        end_offset += 1;
    }

    // Create selection from cursor to end of line
    const end_col = col + (end_offset - offset);
    const delete_sel = Cursor.Selection{
        .anchor = primary.head,
        .head = Cursor.Position{ .line = primary.head.line, .col = end_col },
    };

    _ = Actions.deleteSelection(buffer, delete_sel, null) catch {
        return Result.err("Failed to delete");
    };

    buffer.metadata.markModified();
    return Result.ok();
}

/// Indent current line or selection
fn indentLine(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };

    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const range = primary.range();

    // Indent all lines in selection
    var current_line = range.start.line;
    while (current_line <= range.end.line) {
        const line_start_pos = Cursor.Position{ .line = current_line, .col = 0 };
        const line_start_sel = Cursor.Selection.cursor(line_start_pos);

        _ = Actions.insertText(buffer, line_start_sel, "    ") catch {
            return Result.err("Failed to indent");
        };

        current_line += 1;
    }

    buffer.metadata.markModified();
    return Result.ok();
}

/// Dedent current line or selection
fn dedentLine(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };

    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer ctx.editor.allocator.free(text);

    const range = primary.range();

    // Dedent all lines in selection (in reverse to maintain positions)
    var current_line_signed: isize = @intCast(range.end.line);
    while (current_line_signed >= @as(isize, @intCast(range.start.line))) : (current_line_signed -= 1) {
        const current_line: usize = @intCast(current_line_signed);

        // Find line start in text
        var line: usize = 0;
        var offset: usize = 0;
        while (offset < text.len and line < current_line) {
            if (text[offset] == '\n') {
                line += 1;
            }
            offset += 1;
        }

        // Count leading spaces/tabs (up to 4 spaces or 1 tab)
        var spaces_to_remove: usize = 0;
        var check_offset = offset;
        while (check_offset < text.len and spaces_to_remove < 4 and text[check_offset] != '\n') {
            if (text[check_offset] == ' ') {
                spaces_to_remove += 1;
                check_offset += 1;
            } else if (text[check_offset] == '\t') {
                spaces_to_remove = 1; // Remove one tab
                break;
            } else {
                break; // Non-whitespace, stop
            }
        }

        // Remove the spaces
        if (spaces_to_remove > 0) {
            const delete_sel = Cursor.Selection{
                .anchor = Cursor.Position{ .line = current_line, .col = 0 },
                .head = Cursor.Position{ .line = current_line, .col = spaces_to_remove },
            };
            _ = Actions.deleteSelection(buffer, delete_sel, null) catch {
                return Result.err("Failed to dedent");
            };
        }
    }

    buffer.metadata.markModified();
    return Result.ok();
}

/// Switch to next buffer
fn nextBuffer(ctx: *Context) Result {
    const current_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };

    const buffers = ctx.editor.buffer_manager.listBuffers();
    if (buffers.len <= 1) {
        return Result.err("No other buffers");
    }

    // Find current buffer index
    var current_index: ?usize = null;
    for (buffers, 0..) |buffer, i| {
        if (buffer.metadata.id == current_id) {
            current_index = i;
            break;
        }
    }

    if (current_index) |idx| {
        const next_idx = (idx + 1) % buffers.len;
        const next_id = buffers[next_idx].metadata.id;
        ctx.editor.buffer_manager.switchTo(next_id) catch {
            return Result.err("Failed to switch buffer");
        };

        // Reset selections for new buffer
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, .{ .line = 0, .col = 0 }) catch {};
        ctx.editor.scroll_offset = 0;

        return Result.ok();
    }

    return Result.err("Failed to find current buffer");
}

/// Switch to previous buffer
fn previousBuffer(ctx: *Context) Result {
    const current_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };

    const buffers = ctx.editor.buffer_manager.listBuffers();
    if (buffers.len <= 1) {
        return Result.err("No other buffers");
    }

    // Find current buffer index
    var current_index: ?usize = null;
    for (buffers, 0..) |buffer, i| {
        if (buffer.metadata.id == current_id) {
            current_index = i;
            break;
        }
    }

    if (current_index) |idx| {
        const prev_idx = if (idx == 0) buffers.len - 1 else idx - 1;
        const prev_id = buffers[prev_idx].metadata.id;
        ctx.editor.buffer_manager.switchTo(prev_id) catch {
            return Result.err("Failed to switch buffer");
        };

        // Reset selections for new buffer
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, .{ .line = 0, .col = 0 }) catch {};
        ctx.editor.scroll_offset = 0;

        return Result.ok();
    }

    return Result.err("Failed to find current buffer");
}

/// Close current buffer
fn closeCurrentBuffer(ctx: *Context) Result {
    const current_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };

    const buffers = ctx.editor.buffer_manager.listBuffers();

    // Check if buffer has unsaved changes
    for (buffers) |buffer| {
        if (buffer.metadata.id == current_id and buffer.metadata.modified) {
            return Result.err("Buffer has unsaved changes");
        }
    }

    // If this is the only buffer, create an empty one first
    if (buffers.len == 1) {
        _ = ctx.editor.buffer_manager.createEmpty() catch {
            return Result.err("Failed to create new buffer");
        };
    }

    ctx.editor.buffer_manager.closeBuffer(current_id) catch {
        return Result.err("Failed to close buffer");
    };

    // Reset selections for new buffer
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, .{ .line = 0, .col = 0 }) catch {};
    ctx.editor.scroll_offset = 0;

    return Result.ok();
}

/// Jump to start of buffer (alias for move_file_start)
fn gotoStart(ctx: *Context) Result {
    return moveFileStart(ctx);
}

/// Jump to end of buffer (alias for move_file_end)
fn gotoEnd(ctx: *Context) Result {
    return moveFileEnd(ctx);
}

/// Center cursor on screen
fn centerCursor(ctx: *Context) Result {
    const cursor_pos = ctx.editor.getCursorPosition();
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const total_lines = buffer.lineCount();
    const viewport_height: usize = 24; // TODO: Get from renderer
    const visible_lines = viewport_height -| 2;

    // Center cursor in viewport
    if (cursor_pos.line >= visible_lines / 2) {
        ctx.editor.scroll_offset = cursor_pos.line - (visible_lines / 2);
    } else {
        ctx.editor.scroll_offset = 0;
    }

    // Clamp to valid range
    const max_scroll = if (total_lines > visible_lines) total_lines - visible_lines else 0;
    ctx.editor.scroll_offset = @min(ctx.editor.scroll_offset, max_scroll);

    return Result.ok();
}

/// Scroll viewport up
fn scrollUp(ctx: *Context) Result {
    if (ctx.editor.scroll_offset > 0) {
        ctx.editor.scroll_offset -= 1;
    }
    return Result.ok();
}

/// Scroll viewport down
fn scrollDown(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const total_lines = buffer.lineCount();
    const viewport_height: usize = 24;
    const visible_lines = viewport_height -| 2;
    const max_scroll = if (total_lines > visible_lines) total_lines - visible_lines else 0;

    if (ctx.editor.scroll_offset < max_scroll) {
        ctx.editor.scroll_offset += 1;
    }
    return Result.ok();
}

/// Toggle line comments (add/remove //)
fn toggleLineComment(ctx: *Context) Result {
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };

    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer ctx.editor.allocator.free(text);

    const range = primary.range();

    // Check if all lines are commented
    var all_commented = true;
    var current_line = range.start.line;
    while (current_line <= range.end.line) : (current_line += 1) {
        // Find line start in text
        var line: usize = 0;
        var offset: usize = 0;
        while (offset < text.len and line < current_line) {
            if (text[offset] == '\n') {
                line += 1;
            }
            offset += 1;
        }

        // Skip leading whitespace
        while (offset < text.len and (text[offset] == ' ' or text[offset] == '\t')) {
            offset += 1;
        }

        // Check for //
        if (offset + 2 > text.len or text[offset] != '/' or text[offset + 1] != '/') {
            all_commented = false;
            break;
        }
    }

    // Toggle comments
    if (all_commented) {
        // Remove comments (in reverse to maintain positions)
        var current_line_signed: isize = @intCast(range.end.line);
        while (current_line_signed >= @as(isize, @intCast(range.start.line))) : (current_line_signed -= 1) {
            const line_num: usize = @intCast(current_line_signed);

            // Find line start
            var line: usize = 0;
            var offset: usize = 0;
            while (offset < text.len and line < line_num) {
                if (text[offset] == '\n') {
                    line += 1;
                }
                offset += 1;
            }

            // Find comment marker position (skip whitespace)
            var col: usize = 0;
            while (offset < text.len and (text[offset] == ' ' or text[offset] == '\t')) {
                offset += 1;
                col += 1;
            }

            // Remove // and optional space
            var chars_to_remove: usize = 2; // "//"
            if (offset + 2 < text.len and text[offset + 2] == ' ') {
                chars_to_remove = 3; // "// "
            }

            const delete_sel = Cursor.Selection{
                .anchor = Cursor.Position{ .line = line_num, .col = col },
                .head = Cursor.Position{ .line = line_num, .col = col + chars_to_remove },
            };
            _ = Actions.deleteSelection(buffer, delete_sel, null) catch {};
        }
    } else {
        // Add comments
        current_line = range.start.line;
        while (current_line <= range.end.line) : (current_line += 1) {
            // Find line start
            var line: usize = 0;
            var offset: usize = 0;
            while (offset < text.len and line < current_line) {
                if (text[offset] == '\n') {
                    line += 1;
                }
                offset += 1;
            }

            // Find first non-whitespace position
            var col: usize = 0;
            while (offset < text.len and (text[offset] == ' ' or text[offset] == '\t')) {
                offset += 1;
                col += 1;
            }

            // Insert // at first non-whitespace position
            const insert_pos = Cursor.Position{ .line = current_line, .col = col };
            const insert_sel = Cursor.Selection.cursor(insert_pos);
            _ = Actions.insertText(buffer, insert_sel, "// ") catch {};
        }
    }

    buffer.metadata.markModified();
    return Result.ok();
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

// === Visual/Display Commands ===

/// Toggle syntax highlighting
fn toggleSyntaxHighlighting(ctx: *Context) Result {
    ctx.editor.config.syntax_highlighting = !ctx.editor.config.syntax_highlighting;
    const state = if (ctx.editor.config.syntax_highlighting) "enabled" else "disabled";
    const msg = std.fmt.allocPrint(ctx.editor.allocator, "Syntax highlighting {s}", .{state}) catch {
        return Result.err("Failed to format message");
    };
    defer ctx.editor.allocator.free(msg);
    ctx.editor.messages.add(msg, .info) catch {};
    return Result.ok();
}

// === Window Split Commands ===

/// Split window horizontally (top/bottom)
fn splitHorizontal(ctx: *Context) Result {
    ctx.editor.window_manager.splitActive(.horizontal, 0.5) catch {
        return Result.err("Failed to split window");
    };
    ctx.editor.messages.add("Window split horizontally", .info) catch {};
    return Result.ok();
}

/// Split window vertically (left/right)
fn splitVertical(ctx: *Context) Result {
    ctx.editor.window_manager.splitActive(.vertical, 0.5) catch {
        return Result.err("Failed to split window");
    };
    ctx.editor.messages.add("Window split vertically", .info) catch {};
    return Result.ok();
}

/// Close active window
fn closeWindow(ctx: *Context) Result {
    ctx.editor.window_manager.closeActive() catch |err| {
        return switch (err) {
            error.CannotCloseOnlyWindow => Result.err("Cannot close only window"),
            else => Result.err("Failed to close window"),
        };
    };
    ctx.editor.messages.add("Window closed", .info) catch {};
    return Result.ok();
}

/// Navigate to next window
fn nextWindow(ctx: *Context) Result {
    ctx.editor.window_manager.navigateNext() catch |err| {
        return switch (err) {
            error.NoOtherWindow => Result.err("No other window"),
            else => Result.err("Failed to navigate"),
        };
    };
    ctx.editor.messages.add("Switched to next window", .info) catch {};
    return Result.ok();
}

/// Navigate to previous window
fn previousWindow(ctx: *Context) Result {
    ctx.editor.window_manager.navigatePrevious() catch |err| {
        return switch (err) {
            error.NoOtherWindow => Result.err("No other window"),
            else => Result.err("Failed to navigate"),
        };
    };
    ctx.editor.messages.add("Switched to previous window", .info) catch {};
    return Result.ok();
}

// === Search Commands ===

/// Start incremental search
fn startIncrementalSearch(ctx: *Context) Result {
    ctx.editor.search.startIncremental();
    ctx.editor.messages.add("Search: ", .info) catch {};
    return Result.ok();
}

/// Cancel search
fn cancelSearch(ctx: *Context) Result {
    ctx.editor.search.clear();
    ctx.editor.messages.clear();
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

    // Line manipulation commands
    try registry.register(.{
        .name = "duplicate_line",
        .description = "Duplicate current line (Ctrl+D)",
        .handler = duplicateLine,
        .category = .edit,
    });

    try registry.register(.{
        .name = "join_lines",
        .description = "Join current line with next (J)",
        .handler = joinLines,
        .category = .edit,
    });

    try registry.register(.{
        .name = "delete_to_end",
        .description = "Delete to end of line (D or $d)",
        .handler = deleteToEndOfLine,
        .category = .edit,
    });

    try registry.register(.{
        .name = "indent_line",
        .description = "Indent line or selection (>)",
        .handler = indentLine,
        .category = .edit,
    });

    try registry.register(.{
        .name = "dedent_line",
        .description = "Dedent line or selection (<)",
        .handler = dedentLine,
        .category = .edit,
    });

    try registry.register(.{
        .name = "toggle_comment",
        .description = "Toggle line comments (gcc or Ctrl+/)",
        .handler = toggleLineComment,
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

    // File finder
    try registry.register(.{
        .name = "toggle_file_finder",
        .description = "Toggle file finder (Ctrl P)",
        .handler = toggleFileFinder,
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
        .name = "start_search",
        .description = "Start search with selection (*)",
        .handler = startSearch,
        .category = .search,
    });

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

    // Multi-cursor operations
    try registry.register(.{
        .name = "add_cursor_above",
        .description = "Add cursor on line above (Ctrl+Shift+Up)",
        .handler = addCursorAbove,
        .category = .selection,
    });

    try registry.register(.{
        .name = "add_cursor_below",
        .description = "Add cursor on line below (Ctrl+Shift+Down)",
        .handler = addCursorBelow,
        .category = .selection,
    });

    try registry.register(.{
        .name = "clear_extra_cursors",
        .description = "Clear all extra cursors (Escape)",
        .handler = clearExtraCursors,
        .category = .selection,
    });

    // Buffer management
    try registry.register(.{
        .name = "next_buffer",
        .description = "Switch to next buffer (]b)",
        .handler = nextBuffer,
        .category = .buffer,
    });

    try registry.register(.{
        .name = "previous_buffer",
        .description = "Switch to previous buffer ([b)",
        .handler = previousBuffer,
        .category = .buffer,
    });

    try registry.register(.{
        .name = "close_buffer",
        .description = "Close current buffer (Space c)",
        .handler = closeCurrentBuffer,
        .category = .buffer,
    });

    // Navigation and viewport control
    try registry.register(.{
        .name = "goto_start",
        .description = "Jump to start of buffer (gg)",
        .handler = gotoStart,
        .category = .motion,
    });

    try registry.register(.{
        .name = "goto_end",
        .description = "Jump to end of buffer (G)",
        .handler = gotoEnd,
        .category = .motion,
    });

    try registry.register(.{
        .name = "center_cursor",
        .description = "Center cursor on screen (zz)",
        .handler = centerCursor,
        .category = .view,
    });

    try registry.register(.{
        .name = "scroll_up",
        .description = "Scroll viewport up (Ctrl+Y)",
        .handler = scrollUp,
        .category = .view,
    });

    try registry.register(.{
        .name = "scroll_down",
        .description = "Scroll viewport down (Ctrl+E)",
        .handler = scrollDown,
        .category = .view,
    });

    // Visual/display commands
    try registry.register(.{
        .name = "toggle_syntax",
        .description = "Toggle syntax highlighting (F2)",
        .handler = toggleSyntaxHighlighting,
        .category = .system,
    });

    // Window split commands
    try registry.register(.{
        .name = "split_horizontal",
        .description = "Split window horizontally (Ctrl+w s)",
        .handler = splitHorizontal,
        .category = .view,
    });

    try registry.register(.{
        .name = "split_vertical",
        .description = "Split window vertically (Ctrl+w v)",
        .handler = splitVertical,
        .category = .view,
    });

    try registry.register(.{
        .name = "close_window",
        .description = "Close active window (Ctrl+w q)",
        .handler = closeWindow,
        .category = .view,
    });

    try registry.register(.{
        .name = "next_window",
        .description = "Navigate to next window (Space w)",
        .handler = nextWindow,
        .category = .view,
    });

    try registry.register(.{
        .name = "previous_window",
        .description = "Navigate to previous window (Space W)",
        .handler = previousWindow,
        .category = .view,
    });

    // Search commands
    try registry.register(.{
        .name = "incremental_search",
        .description = "Start incremental search (/)",
        .handler = startIncrementalSearch,
        .category = .search,
    });

    try registry.register(.{
        .name = "cancel_search",
        .description = "Cancel search (Escape)",
        .handler = cancelSearch,
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
