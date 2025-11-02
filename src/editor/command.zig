//! Command registry and execution system
//! Composable commands for modal editing

const std = @import("std");

// Forward declare Editor to avoid circular dependency
const EditorModule = @import("editor.zig");
pub const Editor = EditorModule.Editor;
const PendingCommand = EditorModule.PendingCommand;

const LspHandlers = @import("../lsp/handlers.zig");

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
        motion, // Cursor movement
        edit, // Text editing
        selection, // Selection manipulation
        buffer, // Buffer operations
        mode, // Mode changes
        file, // File I/O
        search, // Search/replace
        view, // Viewport control
        system, // System commands
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
            const result = cmd.handler(ctx);

            // Record action for repeat if it succeeded and should be recorded
            switch (result) {
                .success => {
                    const Repeat = @import("repeat.zig");
                    if (Repeat.RepeatSystem.shouldRecord(name)) {
                        ctx.editor.repeat_system.recordAction(name) catch {};
                    }
                },
                .error_msg => {},
            }

            return result;
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
const Undo = @import("undo.zig");
const Registers = @import("registers.zig");
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

/// Jump to matching bracket
fn jumpToMatchingBracket(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.jumpToMatchingBracket(primary_sel, buffer) catch {
        return Result.err("Failed to find matching bracket");
    };

    if (new_sel.head.eql(primary_sel.head)) {
        return Result.err("No matching bracket found");
    }

    return applyMotion(ctx, new_sel);
}

// Find/Till Character Motions

/// Find character forward (f command)
///
/// Initiates find-forward motion by activating the prompt system.
/// Completion occurs in completeFindChar after user provides character input.
/// Updates find_till_state for repeat commands (;/,).
fn findCharForward(ctx: *Context) Result {
    ctx.editor.pending_command = PendingCommand{ .find_char = .{ .forward = true, .till = false } };
    ctx.editor.prompt.show("Find char:", .character);
    return Result.ok();
}

/// Find character backward (F command)
///
/// Initiates find-backward motion by activating the prompt system.
/// Completion occurs in completeFindChar after user provides character input.
/// Updates find_till_state for repeat commands (;/,).
fn findCharBackward(ctx: *Context) Result {
    ctx.editor.pending_command = PendingCommand{ .find_char = .{ .forward = false, .till = false } };
    ctx.editor.prompt.show("Find char backward:", .character);
    return Result.ok();
}

/// Till character forward (t command)
///
/// Initiates till-forward motion (stops before target character).
/// Completion occurs in completeFindChar after user provides character input.
/// Updates find_till_state for repeat commands (;/,).
fn tillCharForward(ctx: *Context) Result {
    ctx.editor.pending_command = PendingCommand{ .find_char = .{ .forward = true, .till = true } };
    ctx.editor.prompt.show("Till char:", .character);
    return Result.ok();
}

/// Till character backward (T command)
///
/// Initiates till-backward motion (stops after target character).
/// Completion occurs in completeFindChar after user provides character input.
/// Updates find_till_state for repeat commands (;/,).
fn tillCharBackward(ctx: *Context) Result {
    ctx.editor.pending_command = PendingCommand{ .find_char = .{ .forward = false, .till = true } };
    ctx.editor.prompt.show("Till char backward:", .character);
    return Result.ok();
}

fn repeatFindTill(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    if (ctx.editor.find_till_state.char == null) {
        return Result.err("No previous find/till operation");
    }

    const new_sel = Motions.repeatFind(primary_sel, buffer, ctx.editor.find_till_state);

    if (new_sel.head.eql(primary_sel.head)) {
        return Result.err("Character not found");
    }

    return applyMotion(ctx, new_sel);
}

fn reverseFindTill(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    if (ctx.editor.find_till_state.char == null) {
        return Result.err("No previous find/till operation");
    }

    const new_sel = Motions.reverseFind(primary_sel, buffer, ctx.editor.find_till_state);

    if (new_sel.head.eql(primary_sel.head)) {
        return Result.err("Character not found");
    }

    return applyMotion(ctx, new_sel);
}

// Enhanced Text Objects

fn selectParagraphAround(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectParagraphAround(buffer, primary_sel, ctx.editor.allocator) catch {
        return Result.err("Failed to select paragraph");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

fn selectParagraphInside(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectParagraphInside(buffer, primary_sel, ctx.editor.allocator) catch {
        return Result.err("Failed to select paragraph");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

fn selectIndentAround(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectIndentAround(buffer, primary_sel, ctx.editor.allocator) catch {
        return Result.err("Failed to select indent level");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

fn selectIndentInside(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectIndentInside(buffer, primary_sel, ctx.editor.allocator) catch {
        return Result.err("Failed to select indent level");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

fn selectLineAround(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectLineAround(buffer, primary_sel, ctx.editor.allocator) catch {
        return Result.err("Failed to select line");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

fn selectLineInside(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectLineInside(buffer, primary_sel, ctx.editor.allocator) catch {
        return Result.err("Failed to select line");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

fn selectBufferAround(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectBufferAround(buffer, primary_sel, ctx.editor.allocator) catch {
        return Result.err("Failed to select buffer");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

fn selectBufferInside(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectBufferInside(buffer, primary_sel, ctx.editor.allocator) catch {
        return Result.err("Failed to select buffer");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
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

    // Get mutable active buffer
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };

    // Apply undo operations to buffer
    Undo.UndoHistory.applyUndo(group, &buffer.rope, ctx.editor.allocator) catch {
        return Result.err("Failed to apply undo operations");
    };

    // Restore cursor position
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, group.cursor_before) catch {
        return Result.err("Failed to restore cursor");
    };

    // Mark buffer as modified
    buffer.metadata.modified = true;

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

/// Save all modified buffers
fn saveAllBuffers(ctx: *Context) Result {
    var saved_count: usize = 0;
    var skipped_count: usize = 0;

    // Access buffers mutably through buffer_manager
    for (ctx.editor.buffer_manager.buffers.items) |*buffer| {
        if (buffer.metadata.modified) {
            if (buffer.metadata.filepath != null) {
                buffer.save() catch {
                    skipped_count += 1;
                    continue;
                };
                saved_count += 1;
            } else {
                // Skip unsaved buffers without filepath
                skipped_count += 1;
            }
        }
    }

    if (saved_count == 0 and skipped_count == 0) {
        ctx.editor.messages.add("No modified buffers", .info) catch {};
        return Result.ok();
    }

    var msg_buf: [128]u8 = undefined;
    const msg = if (skipped_count > 0)
        std.fmt.bufPrint(&msg_buf, "Saved {d} buffer(s), skipped {d}", .{ saved_count, skipped_count }) catch "Saved buffers"
    else
        std.fmt.bufPrint(&msg_buf, "Saved {d} buffer(s)", .{saved_count}) catch "Saved buffers";

    ctx.editor.messages.add(msg, .success) catch {};
    return Result.ok();
}

/// Force close current buffer without saving
fn forceCloseBuffer(ctx: *Context) Result {
    const current_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };

    const buffers = ctx.editor.buffer_manager.listBuffers();

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

    ctx.editor.messages.add("Buffer closed", .info) catch {};
    return Result.ok();
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

/// Write configuration to file
fn configWrite(ctx: *Context) Result {
    // Get config file path (XDG_CONFIG_HOME/aesop/config.conf or ~/.config/aesop/config.conf)
    const config_dir_path = blk: {
        if (std.process.getEnvVarOwned(ctx.editor.allocator, "XDG_CONFIG_HOME")) |xdg_config_home| {
            defer ctx.editor.allocator.free(xdg_config_home);
            break :blk std.fs.path.join(ctx.editor.allocator, &[_][]const u8{ xdg_config_home, "aesop" }) catch {
                return Result.err("Failed to construct config directory path");
            };
        } else |_| {
            if (std.process.getEnvVarOwned(ctx.editor.allocator, "HOME")) |home| {
                defer ctx.editor.allocator.free(home);
                break :blk std.fs.path.join(ctx.editor.allocator, &[_][]const u8{ home, ".config", "aesop" }) catch {
                    return Result.err("Failed to construct config directory path");
                };
            } else |_| {
                return Result.err("Could not determine config directory (HOME not set)");
            }
        }
    };
    defer ctx.editor.allocator.free(config_dir_path);

    // Create directory if it doesn't exist
    std.fs.cwd().makePath(config_dir_path) catch {
        return Result.err("Failed to create config directory");
    };

    // Construct full config file path
    const config_file_path = std.fs.path.join(
        ctx.editor.allocator,
        &[_][]const u8{ config_dir_path, "config.conf" },
    ) catch {
        return Result.err("Failed to construct config file path");
    };
    defer ctx.editor.allocator.free(config_file_path);

    // Save config to file
    ctx.editor.config.saveToFile(config_file_path) catch {
        return Result.err("Failed to write config file");
    };

    var msg_buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "Configuration written to {s}", .{config_file_path}) catch "Configuration written";
    ctx.editor.messages.add(msg, .success) catch {};

    return Result.ok();
}

/// Show current configuration settings
fn configShow(ctx: *Context) Result {
    const cfg = &ctx.editor.config;
    var msg_buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &msg_buf,
        "tab_width={d} expand_tabs={s} line_numbers={s} relative_line_numbers={s} syntax_highlighting={s}",
        .{
            cfg.tab_width,
            if (cfg.expand_tabs) "true" else "false",
            if (cfg.line_numbers) "true" else "false",
            if (cfg.relative_line_numbers) "true" else "false",
            if (cfg.syntax_highlighting) "true" else "false",
        },
    ) catch "Config settings";

    ctx.editor.messages.add(msg, .info) catch {};
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

/// Toggle buffer switcher
fn toggleBufferSwitcher(ctx: *Context) Result {
    if (ctx.editor.buffer_switcher_visible) {
        ctx.editor.buffer_switcher_visible = false;
        ctx.editor.buffer_switcher_selected = 0;
    } else {
        ctx.editor.buffer_switcher_visible = true;
        ctx.editor.buffer_switcher_selected = 0;
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

/// Select the word under cursor (text object)
fn selectCurrentWord(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const word_sel = Actions.selectWord(buffer, primary_sel) catch {
        return Result.err("Failed to select word");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, word_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

/// Delete word under cursor (text object)
fn deleteCurrentWord(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.deleteWord(buffer, primary_sel) catch {
            return Result.err("Failed to delete word");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
            return Result.err("Failed to update cursor");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Change word under cursor (delete and enter insert mode)
fn changeCurrentWord(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.changeWord(buffer, primary_sel) catch {
            return Result.err("Failed to change word");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
            return Result.err("Failed to update cursor");
        };

        // Switch to insert mode
        ctx.editor.mode_manager.transitionTo(.insert) catch {};

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Convert selection to uppercase
fn uppercaseSelection(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.uppercaseSelection(buffer, primary_sel, ctx.editor.allocator) catch {
            return Result.err("Failed to convert to uppercase");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
            return Result.err("Failed to update selection");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Convert selection to lowercase
fn lowercaseSelection(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.lowercaseSelection(buffer, primary_sel, ctx.editor.allocator) catch {
            return Result.err("Failed to convert to lowercase");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
            return Result.err("Failed to update selection");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Convert selection to title case
fn titlecaseSelection(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.titlecaseSelection(buffer, primary_sel, ctx.editor.allocator) catch {
            return Result.err("Failed to convert to title case");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
            return Result.err("Failed to update selection");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Select inside parentheses
fn selectInnerParen(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectInnerPair(buffer, primary_sel, .paren, ctx.editor.allocator) catch {
        return Result.err("Failed to select inside parentheses");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

/// Delete inside parentheses
fn deleteInnerParen(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.deleteInnerPair(buffer, primary_sel, .paren, ctx.editor.allocator) catch {
            return Result.err("Failed to delete inside parentheses");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
            return Result.err("Failed to update cursor");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Change inside parentheses
fn changeInnerParen(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.changeInnerPair(buffer, primary_sel, .paren, ctx.editor.allocator) catch {
            return Result.err("Failed to change inside parentheses");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
            return Result.err("Failed to update cursor");
        };

        ctx.editor.mode_manager.transitionTo(.insert) catch {};
        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Select inside quotes (double)
fn selectInnerQuote(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectInnerPair(buffer, primary_sel, .double_quote, ctx.editor.allocator) catch {
        return Result.err("Failed to select inside quotes");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

/// Select inside brackets
fn selectInnerBracket(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectInnerPair(buffer, primary_sel, .bracket, ctx.editor.allocator) catch {
        return Result.err("Failed to select inside brackets");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

/// Delete inside brackets
fn deleteInnerBracket(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.deleteInnerPair(buffer, primary_sel, .bracket, ctx.editor.allocator) catch {
            return Result.err("Failed to delete inside brackets");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
            return Result.err("Failed to update cursor");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Select inside braces
fn selectInnerBrace(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Actions.selectInnerPair(buffer, primary_sel, .brace, ctx.editor.allocator) catch {
        return Result.err("Failed to select inside braces");
    };

    ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

/// Delete inside braces
fn deleteInnerBrace(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.deleteInnerPair(buffer, primary_sel, .brace, ctx.editor.allocator) catch {
            return Result.err("Failed to delete inside braces");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
            return Result.err("Failed to update cursor");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Change inside braces
fn changeInnerBrace(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");
        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

        const new_sel = Actions.changeInnerPair(buffer, primary_sel, .brace, ctx.editor.allocator) catch {
            return Result.err("Failed to change inside braces");
        };
        buffer.metadata.markModified();

        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch {
            return Result.err("Failed to update cursor");
        };

        ctx.editor.mode_manager.transitionTo(.insert) catch {};
        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Set mark at cursor position (m command)
///
/// Initiates mark-setting by activating the prompt system.
/// Completion occurs in completeSetMark after user provides register name.
/// Marks persist across buffers and can be used for cross-file navigation.
fn setMark(ctx: *Context) Result {
    ctx.editor.pending_command = .set_mark;
    ctx.editor.prompt.show("Mark:", .character);
    return Result.ok();
}

/// Jump to mark
fn jumpToMark(ctx: *Context) Result {
    ctx.editor.pending_command = .goto_mark;
    ctx.editor.prompt.show("Go to mark:", .character);
    return Result.ok();
}

/// List all marks
fn listMarks(ctx: *Context) Result {
    const marks = ctx.editor.marks.listMarks(ctx.editor.allocator) catch {
        return Result.err("Failed to list marks");
    };
    defer ctx.editor.allocator.free(marks);

    if (marks.len == 0) {
        ctx.editor.messages.add("No marks set", .info) catch {};
        return Result.ok();
    }

    // Show first mark info (TODO: show in palette or buffer)
    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{d} mark(s) set", .{marks.len}) catch "Marks exist";
    ctx.editor.messages.add(msg, .info) catch {};

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

/// Select all text in buffer
fn selectAll(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    // Get the end position (last line, last column)
    const line_count = buffer.lineCount();
    if (line_count == 0) {
        return Result.ok();
    }

    const last_line = line_count - 1;
    const allocator = ctx.editor.allocator;

    // Get length of last line
    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer allocator.free(text);

    var current_line: usize = 0;
    var offset: usize = 0;
    var line_start: usize = 0;

    // Find the last line
    while (offset < text.len) {
        if (text[offset] == '\n') {
            current_line += 1;
            if (current_line == last_line + 1) break;
            line_start = offset + 1;
        }
        offset += 1;
    }

    // Calculate last column
    var last_col: usize = 0;
    while (line_start < text.len and text[line_start] != '\n') {
        last_col += 1;
        line_start += 1;
    }

    // Create selection from start to end
    const selection = Cursor.Selection.init(
        Cursor.Position{ .line = 0, .col = 0 },
        Cursor.Position{ .line = last_line, .col = last_col },
    );

    ctx.editor.selections.setSingleSelection(allocator, selection) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

/// Select entire current line
fn selectLine(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const cursor_pos = ctx.editor.getCursorPosition();
    const allocator = ctx.editor.allocator;

    // Get line length
    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer allocator.free(text);

    var current_line: usize = 0;
    var offset: usize = 0;
    var line_start: usize = 0;

    // Find the target line
    while (offset < text.len and current_line < cursor_pos.line) {
        if (text[offset] == '\n') {
            current_line += 1;
            line_start = offset + 1;
        }
        offset += 1;
    }

    if (current_line == cursor_pos.line) {
        line_start = offset;
    }

    // Find line end
    var line_end = line_start;
    while (line_end < text.len and text[line_end] != '\n') {
        line_end += 1;
    }

    const line_len = line_end - line_start;

    // Select from line start to line end
    const selection = Cursor.Selection.init(
        Cursor.Position{ .line = cursor_pos.line, .col = 0 },
        Cursor.Position{ .line = cursor_pos.line, .col = line_len },
    );

    ctx.editor.selections.setSingleSelection(allocator, selection) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

/// Extend selection to end of line
fn extendToLineEnd(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const allocator = ctx.editor.allocator;
    const head = primary.head;

    // Get line length
    const text = buffer.getText() catch {
        return Result.err("Failed to get buffer text");
    };
    defer allocator.free(text);

    var current_line: usize = 0;
    var offset: usize = 0;
    var line_start: usize = 0;

    // Find the current line
    while (offset < text.len and current_line < head.line) {
        if (text[offset] == '\n') {
            current_line += 1;
            line_start = offset + 1;
        }
        offset += 1;
    }

    if (current_line == head.line) {
        line_start = offset;
    }

    // Find line end
    var line_end = line_start;
    while (line_end < text.len and text[line_end] != '\n') {
        line_end += 1;
    }

    const line_len = line_end - line_start;

    // Extend selection to end of line
    const new_selection = primary.moveTo(Cursor.Position{ .line = head.line, .col = line_len });

    ctx.editor.selections.setSingleSelection(allocator, new_selection) catch {
        return Result.err("Failed to update selection");
    };

    return Result.ok();
}

/// Move to next paragraph
fn moveToNextParagraph(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const new_sel = Motions.moveNextParagraph(primary_sel, buffer);

    return applyMotion(ctx, new_sel);
}

/// Move to previous paragraph
fn moveToPrevParagraph(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
        return Result.err("No selection");
    };

    const new_sel = Motions.movePrevParagraph(primary_sel, buffer);

    return applyMotion(ctx, new_sel);
}

/// Transpose characters at cursor
fn transposeCharacters(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse {
            return Result.err("No active buffer");
        };

        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
            return Result.err("No selection");
        };

        _ = Actions.transposeChars(buffer, primary_sel, ctx.editor.allocator) catch {
            return Result.err("Failed to transpose characters");
        };

        buffer.metadata.markModified();
        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Transpose lines (swap current with previous)
fn transposeLines(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse {
            return Result.err("No active buffer");
        };

        const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
            return Result.err("No selection");
        };

        _ = Actions.transposeLines(buffer, primary_sel, ctx.editor.allocator) catch {
            return Result.err("Failed to transpose lines");
        };

        buffer.metadata.markModified();
        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Sort selected lines alphabetically
fn sortLines(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse {
            return Result.err("No active buffer");
        };

        const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
            return Result.err("No selection");
        };

        const range = primary.range();
        const allocator = ctx.editor.allocator;

        // Get buffer text
        const text = buffer.getText() catch {
            return Result.err("Failed to get buffer text");
        };
        defer allocator.free(text);

        // Extract lines in range
        var lines = std.ArrayList([]const u8).empty;
        defer {
            for (lines.items) |line| {
                allocator.free(line);
            }
            lines.deinit(allocator);
        }

        var current_line: usize = 0;
        var offset: usize = 0;
        var line_start: usize = 0;

        // Find start of first line in selection
        while (offset < text.len and current_line < range.start.line) {
            if (text[offset] == '\n') {
                current_line += 1;
                line_start = offset + 1;
            }
            offset += 1;
        }

        line_start = offset;
        const selection_start = line_start;

        // Collect lines in range
        while (offset < text.len and current_line <= range.end.line) {
            if (text[offset] == '\n' or offset == text.len - 1) {
                const line_end = if (text[offset] == '\n') offset else offset + 1;
                const line_text = text[line_start..line_end];
                const line_copy = allocator.dupe(u8, line_text) catch {
                    return Result.err("Failed to copy line");
                };
                lines.append(allocator, line_copy) catch {
                    return Result.err("Failed to add line");
                };

                if (text[offset] == '\n') {
                    current_line += 1;
                    line_start = offset + 1;
                }
            }
            offset += 1;
        }

        const selection_end = offset;

        if (lines.items.len == 0) return Result.ok();

        // Sort lines
        std.mem.sort([]const u8, lines.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Build sorted text
        var sorted = std.ArrayList(u8).empty;
        defer sorted.deinit(allocator);

        for (lines.items, 0..) |line, i| {
            sorted.appendSlice(allocator, line) catch {
                return Result.err("Failed to build sorted text");
            };
            if (i < lines.items.len - 1) {
                sorted.append(allocator, '\n') catch {
                    return Result.err("Failed to build sorted text");
                };
            }
        }

        // Replace selection with sorted text
        buffer.rope.delete(selection_start, selection_end) catch {
            return Result.err("Failed to delete selection");
        };
        buffer.rope.insert(selection_start, sorted.items) catch {
            return Result.err("Failed to insert sorted text");
        };

        buffer.metadata.markModified();
        ctx.editor.messages.add("Lines sorted", .info) catch {};

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Remove duplicate lines from selection
fn uniqueLines(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse {
            return Result.err("No active buffer");
        };

        const primary = ctx.editor.selections.primary(ctx.editor.allocator) orelse {
            return Result.err("No selection");
        };

        const range = primary.range();
        const allocator = ctx.editor.allocator;

        // Get buffer text
        const text = buffer.getText() catch {
            return Result.err("Failed to get buffer text");
        };
        defer allocator.free(text);

        // Extract and deduplicate lines
        var seen = std.StringHashMap(void).init(allocator);
        defer seen.deinit();

        var unique = std.ArrayList([]const u8).empty;
        defer {
            for (unique.items) |line| {
                allocator.free(line);
            }
            unique.deinit(allocator);
        }

        var current_line: usize = 0;
        var offset: usize = 0;
        var line_start: usize = 0;

        // Find start of selection
        while (offset < text.len and current_line < range.start.line) {
            if (text[offset] == '\n') {
                current_line += 1;
                line_start = offset + 1;
            }
            offset += 1;
        }

        line_start = offset;
        const selection_start = line_start;

        // Collect unique lines
        while (offset < text.len and current_line <= range.end.line) {
            if (text[offset] == '\n' or offset == text.len - 1) {
                const line_end = if (text[offset] == '\n') offset else offset + 1;
                const line_text = text[line_start..line_end];

                // Check if we've seen this line
                if (seen.get(line_text) == null) {
                    const line_copy = allocator.dupe(u8, line_text) catch {
                        return Result.err("Failed to copy line");
                    };
                    unique.append(allocator, line_copy) catch {
                        return Result.err("Failed to add line");
                    };
                    seen.put(line_text, {}) catch {};
                }

                if (text[offset] == '\n') {
                    current_line += 1;
                    line_start = offset + 1;
                }
            }
            offset += 1;
        }

        const selection_end = offset;

        if (unique.items.len == 0) return Result.ok();

        // Build unique text
        var result_text = std.ArrayList(u8).empty;
        defer result_text.deinit(allocator);

        for (unique.items, 0..) |line, i| {
            result_text.appendSlice(allocator, line) catch {
                return Result.err("Failed to build unique text");
            };
            if (i < unique.items.len - 1) {
                result_text.append(allocator, '\n') catch {
                    return Result.err("Failed to build unique text");
                };
            }
        }

        // Replace selection
        buffer.rope.delete(selection_start, selection_end) catch {
            return Result.err("Failed to delete selection");
        };
        buffer.rope.insert(selection_start, result_text.items) catch {
            return Result.err("Failed to insert unique text");
        };

        buffer.metadata.markModified();

        var msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Removed duplicates", .{}) catch "Duplicates removed";
        ctx.editor.messages.add(msg, .info) catch {};

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Repeat last action (like vim's dot command)
fn repeatLastAction(ctx: *Context) Result {
    const last_action = ctx.editor.repeat_system.getLastAction();
    if (last_action == null) {
        return Result.err("No action to repeat");
    }

    const action = last_action.?;
    const command = ctx.editor.command_registry.get(action.command_name);
    if (command == null) {
        return Result.err("Command no longer available");
    }

    // Mark that we're replaying to prevent recursive recording
    ctx.editor.repeat_system.startReplay();
    defer ctx.editor.repeat_system.endReplay();

    // Execute the command
    const result = command.?.handler(ctx);

    return result;
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

/// Jump to specific line number
fn gotoLine(ctx: *Context) Result {
    // This would typically get the line number from a prompt/input
    // For now, this is a placeholder that would need UI integration
    // A real implementation would:
    // 1. Prompt user for line number
    // 2. Parse the input
    // 3. Jump to that line

    // Placeholder: Jump to line 1 as demonstration
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const total_lines = buffer.lineCount();

    // TODO: Get line number from user input
    // For now this is just the function structure
    _ = total_lines;

    ctx.editor.messages.add("Goto line command (line number input needed)", .info) catch {};
    return Result.ok();
}

/// Jump to specific line number (with parameter)
fn gotoLineNumber(ctx: *Context, line_number: usize) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const total_lines = buffer.lineCount();

    // Validate line number (1-indexed for user, 0-indexed internally)
    if (line_number == 0) {
        return Result.err("Line number must be >= 1");
    }

    if (line_number > total_lines) {
        // Jump to last line instead of erroring
        const target_line = if (total_lines > 0) total_lines - 1 else 0;
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, .{
            .line = target_line,
            .col = 0,
        }) catch {
            return Result.err("Failed to move cursor");
        };

        var msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Line {d} out of range, jumped to end", .{line_number}) catch "Jumped to end";
        ctx.editor.messages.add(msg, .warning) catch {};
        return Result.ok();
    }

    // Jump to line (convert from 1-indexed to 0-indexed)
    const target_line = line_number - 1;
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, .{
        .line = target_line,
        .col = 0,
    }) catch {
        return Result.err("Failed to move cursor");
    };

    // Update scroll to show the line
    ctx.editor.scroll_offset = if (target_line > 5) target_line - 5 else 0;

    var msg_buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "Line {d}/{d}", .{ line_number, total_lines }) catch "Jumped to line";
    ctx.editor.messages.add(msg, .success) catch {};

    return Result.ok();
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

/// Scroll viewport up by one page
fn scrollPageUp(ctx: *Context) Result {
    const viewport_height: usize = 24;
    const visible_lines = viewport_height -| 2;

    if (ctx.editor.scroll_offset >= visible_lines) {
        ctx.editor.scroll_offset -= visible_lines;
    } else {
        ctx.editor.scroll_offset = 0;
    }
    return Result.ok();
}

/// Scroll viewport down by one page
fn scrollPageDown(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const total_lines = buffer.lineCount();
    const viewport_height: usize = 24;
    const visible_lines = viewport_height -| 2;
    const max_scroll = if (total_lines > visible_lines) total_lines - visible_lines else 0;

    ctx.editor.scroll_offset += visible_lines;
    ctx.editor.scroll_offset = @min(ctx.editor.scroll_offset, max_scroll);

    return Result.ok();
}

/// Scroll viewport up by half a page
fn scrollHalfPageUp(ctx: *Context) Result {
    const viewport_height: usize = 24;
    const visible_lines = viewport_height -| 2;
    const half_page = visible_lines / 2;

    if (ctx.editor.scroll_offset >= half_page) {
        ctx.editor.scroll_offset -= half_page;
    } else {
        ctx.editor.scroll_offset = 0;
    }
    return Result.ok();
}

/// Scroll viewport down by half a page
fn scrollHalfPageDown(ctx: *Context) Result {
    const buffer = ctx.editor.buffer_manager.getActiveBuffer() orelse {
        return Result.err("No active buffer");
    };

    const total_lines = buffer.lineCount();
    const viewport_height: usize = 24;
    const visible_lines = viewport_height -| 2;
    const max_scroll = if (total_lines > visible_lines) total_lines - visible_lines else 0;
    const half_page = visible_lines / 2;

    ctx.editor.scroll_offset += half_page;
    ctx.editor.scroll_offset = @min(ctx.editor.scroll_offset, max_scroll);

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

    // Get mutable active buffer
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse {
        return Result.err("No active buffer");
    };
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse {
        return Result.err("No active buffer");
    };

    // Apply redo operations to buffer
    Undo.UndoHistory.applyRedo(group, &buffer.rope, ctx.editor.allocator) catch {
        return Result.err("Failed to apply redo operations");
    };

    // Restore cursor position
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, group.cursor_after) catch {
        return Result.err("Failed to restore cursor");
    };

    // Mark buffer as modified
    buffer.metadata.modified = true;

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

// === Line Operation Commands ===

/// Move line up
fn moveLineUp(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");

        // Apply to primary selection
        const sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
        const new_sel = Actions.moveLineUp(buffer, sel) catch {
            return Result.err("Failed to move line up");
        };
        ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
            return Result.err("Failed to update selection");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
}

/// Move line down
fn moveLineDown(ctx: *Context) Result {
    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");

        // Apply to primary selection
        const sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");
        const new_sel = Actions.moveLineDown(buffer, sel) catch {
            return Result.err("Failed to move line down");
        };
        ctx.editor.selections.setSingleSelection(ctx.editor.allocator, new_sel) catch {
            return Result.err("Failed to update selection");
        };

        return Result.ok();
    }
    return Result.err("No active buffer");
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

/// Replace next occurrence of search query
fn replaceNext(ctx: *Context) Result {
    if (ctx.editor.search.query_len == 0) {
        return Result.err("No search query");
    }

    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");

        // Get buffer text
        const text = buffer.getText() catch {
            return Result.err("Failed to get buffer text");
        };
        defer ctx.editor.allocator.free(text);

        // Get current cursor position
        const cursor_pos = ctx.editor.getCursorPosition();

        // Find next match
        const match = ctx.editor.search.findNext(text, cursor_pos);
        if (match == null) {
            return Result.err("No more matches");
        }

        const m = match.?;

        // Convert positions to byte offsets
        const start_offset = Actions.positionToByteOffset(buffer, m.start) catch {
            return Result.err("Invalid match position");
        };
        const end_offset = Actions.positionToByteOffset(buffer, m.end) catch {
            return Result.err("Invalid match position");
        };

        // Delete the match
        buffer.rope.delete(start_offset, end_offset) catch {
            return Result.err("Failed to delete match");
        };

        // Insert replacement text
        const replace_text = ctx.editor.search.getReplaceText();
        buffer.rope.insert(start_offset, replace_text) catch {
            return Result.err("Failed to insert replacement");
        };

        buffer.metadata.markModified();
        ctx.editor.search.replacements_made += 1;

        // Move cursor to end of replacement
        ctx.editor.selections.setSingleCursor(ctx.editor.allocator, .{
            .line = m.start.line,
            .col = m.start.col + replace_text.len,
        }) catch {};

        return Result.ok();
    }

    return Result.err("No active buffer");
}

/// Replace all occurrences of search query
fn replaceAll(ctx: *Context) Result {
    if (ctx.editor.search.query_len == 0) {
        return Result.err("No search query");
    }

    if (ctx.editor.buffer_manager.active_buffer_id) |id| {
        const buffer = ctx.editor.buffer_manager.getBufferMut(id) orelse return Result.err("No active buffer");

        // Get buffer text
        const text = buffer.getText() catch {
            return Result.err("Failed to get buffer text");
        };
        defer ctx.editor.allocator.free(text);

        // Find all matches
        const matches = ctx.editor.search.findAllMatches(text, ctx.editor.allocator) catch {
            return Result.err("Failed to find matches");
        };
        defer ctx.editor.allocator.free(matches);

        if (matches.len == 0) {
            return Result.err("No matches found");
        }

        ctx.editor.search.replacements_made = 0;

        // Replace in reverse order to maintain position validity
        var i: usize = matches.len;
        while (i > 0) {
            i -= 1;
            const m = matches[i];

            // Convert positions to byte offsets
            const start_offset = Actions.positionToByteOffset(buffer, m.start) catch continue;
            const end_offset = Actions.positionToByteOffset(buffer, m.end) catch continue;

            // Delete the match
            buffer.rope.delete(start_offset, end_offset) catch continue;

            // Insert replacement text
            const replace_text = ctx.editor.search.getReplaceText();
            buffer.rope.insert(start_offset, replace_text) catch continue;

            ctx.editor.search.replacements_made += 1;
        }

        buffer.metadata.markModified();

        // Show result message
        var msg_buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Replaced {d} occurrence(s)", .{ctx.editor.search.replacements_made}) catch "Replacements complete";
        ctx.editor.messages.add(msg, .success) catch {};

        return Result.ok();
    }

    return Result.err("No active buffer");
}

// === Macro Commands ===

/// Start recording macro (q command)
///
/// Initiates macro recording by activating the prompt system.
/// Completion occurs in completeRecordMacro after user provides register name.
/// Subsequent commands are captured until stopMacroRecording is called.
/// Macros are stored in registers (a-z) and persist across sessions.
fn startMacroRecording(ctx: *Context) Result {
    ctx.editor.pending_command = .record_macro;
    ctx.editor.prompt.show("Record macro to register:", .character);
    return Result.ok();
}

/// Stop recording macro
fn stopMacroRecording(ctx: *Context) Result {
    ctx.editor.macro_recorder.stopRecording(&ctx.editor.registers) catch |err| {
        return switch (err) {
            error.NotRecording => Result.err("Not recording"),
            else => Result.err("Failed to stop recording"),
        };
    };

    ctx.editor.messages.add("Macro saved", .success) catch {};
    return Result.ok();
}

/// Play macro from register
fn playMacro(ctx: *Context) Result {
    ctx.editor.pending_command = .play_macro;
    ctx.editor.prompt.show("Play macro from register:", .character);
    return Result.ok();
}

// === LSP Commands ===

/// Completion callback handler (called when LSP returns results)
fn lspCompletionCallback(ctx: ?*anyopaque, result_json: []const u8) !void {
    const ResponseParser = @import("../lsp/response_parser.zig");

    // Extract editor from context
    const editor: *Editor = @ptrCast(@alignCast(ctx orelse return error.NullContext));

    // Parse completion response
    const items = ResponseParser.parseCompletionResponse(editor.allocator, result_json) catch |err| {
        std.debug.print("[LSP] Failed to parse completion response: {}\n", .{err});
        editor.messages.add("Failed to parse completion results", .error_msg) catch {};
        return;
    };

    // Clear old items and add new ones
    editor.completion_list.clear();

    for (items) |item| {
        editor.completion_list.addItem(item) catch |err| {
            std.debug.print("[LSP] Failed to add completion item: {}\n", .{err});
            // Free the item we couldn't add
            var mutable_item = item;
            mutable_item.deinit(editor.allocator);
            continue;
        };
    }

    // Free the items array (but not the items themselves - they're now owned by completion_list)
    editor.allocator.free(items);

    std.debug.print("[LSP] Added {} completion items\n", .{editor.completion_list.items.items.len});
}

/// Trigger code completion at cursor position
fn lspTriggerCompletion(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");

    // Get cursor position
    const cursor = (ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No cursor")).head;

    // Show completion list at cursor position
    ctx.editor.completion_list.show(cursor.line, cursor.col);

    // If LSP client is available and initialized, trigger completion request
    if (ctx.editor.lsp_client) |*client| {
        if (client.isReady()) {
            // Get file URI
            const filepath = buffer.metadata.filepath orelse return Result.err("Buffer has no filepath");

            // TODO: Convert filepath to file:// URI
            var uri_buf: [1024]u8 = undefined;
            const uri = std.fmt.bufPrint(&uri_buf, "file://{s}", .{filepath}) catch return Result.err("URI too long");

            // Trigger completion request
            // Note: This is async - results will come via callback
            const request_id = LspHandlers.completion(
                client,
                uri,
                @intCast(cursor.line),
                @intCast(cursor.col),
                lspCompletionCallback,
                ctx.editor, // Pass editor as context
            ) catch {
                ctx.editor.messages.add("Failed to request completion", .error_msg) catch {};
                return Result.ok();
            };

            _ = request_id;
            ctx.editor.messages.add("Completion requested...", .info) catch {};
        } else {
            // LSP not ready, show empty list
            ctx.editor.messages.add("LSP not initialized", .warning) catch {};
        }
    } else {
        // No LSP client, just show UI for manual testing
        ctx.editor.messages.add("LSP not available", .warning) catch {};
    }

    return Result.ok();
}

/// Hide completion list
fn lspHideCompletion(ctx: *Context) Result {
    ctx.editor.completion_list.hide();
    return Result.ok();
}

/// Navigate completion list up
fn lspCompletionPrevious(ctx: *Context) Result {
    ctx.editor.completion_list.selectPrevious();
    return Result.ok();
}

/// Navigate completion list down
fn lspCompletionNext(ctx: *Context) Result {
    ctx.editor.completion_list.selectNext();
    return Result.ok();
}

/// Accept selected completion item
fn lspAcceptCompletion(ctx: *Context) Result {
    const item = ctx.editor.completion_list.getSelectedItem() orelse return Result.err("No completion selected");

    // Get the text to insert (prefer insert_text, fall back to label)
    const text_to_insert = item.insert_text orelse item.label;

    // Get current buffer and cursor
    const buffer_id = ctx.editor.buffer_manager.active_buffer_id orelse return Result.err("No active buffer");
    const buffer = ctx.editor.buffer_manager.getBufferMut(buffer_id) orelse return Result.err("No active buffer");
    const cursor = (ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No cursor")).head;

    // Convert cursor position to byte offset
    // TODO: This is simplified - should handle multi-byte characters properly
    const byte_offset = cursor.line * 80 + cursor.col; // Rough estimate

    // Insert completion text
    buffer.insert(byte_offset, text_to_insert) catch {
        return Result.err("Failed to insert completion");
    };

    // Move cursor forward by inserted text length
    const new_col = cursor.col + text_to_insert.len;
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, .{
        .line = cursor.line,
        .col = new_col,
    }) catch {};

    // Hide completion list
    ctx.editor.completion_list.hide();

    return Result.ok();
}

/// Callback for LSP hover response
fn lspHoverCallback(ctx: ?*anyopaque, result_json: []const u8) !void {
    const ResponseParser = @import("../lsp/response_parser.zig");
    const editor: *Editor = @ptrCast(@alignCast(ctx orelse return error.NullContext));

    // Parse hover response
    const hover_text = ResponseParser.parseHoverResponse(editor.allocator, result_json) catch |err| {
        std.debug.print("[LSP] Failed to parse hover response: {}\n", .{err});
        editor.messages.add("Failed to parse hover information", .error_msg) catch {};
        return;
    };

    // Free old hover content if exists
    if (editor.hover_content) |old_content| {
        editor.allocator.free(old_content);
    }

    // Store new hover content
    editor.hover_content = hover_text;
}

/// Callback for LSP goto definition response
fn lspDefinitionCallback(ctx: ?*anyopaque, result_json: []const u8) !void {
    const ResponseParser = @import("../lsp/response_parser.zig");
    const editor: *Editor = @ptrCast(@alignCast(ctx orelse return error.NullContext));

    // Parse definition response
    const locations = ResponseParser.parseDefinitionResponse(editor.allocator, result_json) catch |err| {
        std.debug.print("[LSP] Failed to parse definition response: {}\n", .{err});
        editor.messages.add("Failed to parse definition location", .error_msg) catch {};
        return;
    };
    defer {
        for (locations) |*loc| {
            loc.deinit(editor.allocator);
        }
        editor.allocator.free(locations);
    }

    if (locations.len == 0) {
        editor.messages.add("No definition found", .info) catch {};
        return;
    }

    // Navigate to first location
    const location = locations[0];

    // Convert file:// URI to filepath
    const uri_prefix = "file://";
    const filepath = if (std.mem.startsWith(u8, location.uri, uri_prefix))
        location.uri[uri_prefix.len..]
    else
        location.uri;

    // Open file and navigate to position
    editor.openFile(filepath) catch |err| {
        std.debug.print("[LSP] Failed to open file {s}: {}\n", .{ filepath, err });
        editor.messages.add("Failed to open definition file", .error_msg) catch {};
        return;
    };

    // Set cursor to definition position
    editor.selections.setSingleCursor(editor.allocator, .{
        .line = location.range.start.line,
        .col = location.range.start.character,
    }) catch {};

    editor.messages.add("Navigated to definition", .success) catch {};
}

/// Go to definition of symbol under cursor
fn lspGotoDefinition(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const client = &(ctx.editor.lsp_client orelse return Result.err("LSP not initialized"));

    // Get cursor position
    const cursor = (ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No cursor")).head;

    // Get file URI
    const filepath = buffer.metadata.filepath orelse return Result.err("Buffer has no file path");
    const uri = ctx.editor.makeFileUri(filepath) catch return Result.err("Failed to create URI");
    defer ctx.editor.allocator.free(uri);

    // Send LSP definition request
    _ = LspHandlers.definition(
        client,
        uri,
        @intCast(cursor.line),
        @intCast(cursor.col),
        lspDefinitionCallback,
        ctx.editor,
    ) catch |err| {
        std.debug.print("[LSP] Failed to request definition: {}\n", .{err});
        return Result.err("LSP definition request failed");
    };

    return Result.ok();
}

/// Show hover information for symbol under cursor
fn lspShowHover(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const client = &(ctx.editor.lsp_client orelse return Result.err("LSP not initialized"));

    // Get cursor position
    const cursor = (ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No cursor")).head;

    // Get file URI
    const filepath = buffer.metadata.filepath orelse return Result.err("Buffer has no file path");
    const uri = ctx.editor.makeFileUri(filepath) catch return Result.err("Failed to create URI");
    defer ctx.editor.allocator.free(uri);

    // Send LSP hover request
    _ = LspHandlers.hover(
        client,
        uri,
        @intCast(cursor.line),
        @intCast(cursor.col),
        lspHoverCallback,
        ctx.editor,
    ) catch |err| {
        std.debug.print("[LSP] Failed to request hover: {}\n", .{err});
        return Result.err("LSP hover request failed");
    };

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

    try registry.register(.{
        .name = "jump_to_matching_bracket",
        .description = "Jump to matching bracket/brace/paren (%)",
        .handler = jumpToMatchingBracket,
        .category = .motion,
    });

    // Find/till character motions
    try registry.register(.{
        .name = "find_char_forward",
        .description = "Find character forward on line (f)",
        .handler = findCharForward,
        .category = .motion,
    });

    try registry.register(.{
        .name = "find_char_backward",
        .description = "Find character backward on line (F)",
        .handler = findCharBackward,
        .category = .motion,
    });

    try registry.register(.{
        .name = "till_char_forward",
        .description = "Till character forward on line (t)",
        .handler = tillCharForward,
        .category = .motion,
    });

    try registry.register(.{
        .name = "till_char_backward",
        .description = "Till character backward on line (T)",
        .handler = tillCharBackward,
        .category = .motion,
    });

    try registry.register(.{
        .name = "repeat_find_till",
        .description = "Repeat last find/till (;)",
        .handler = repeatFindTill,
        .category = .motion,
    });

    try registry.register(.{
        .name = "reverse_find_till",
        .description = "Reverse last find/till (,)",
        .handler = reverseFindTill,
        .category = .motion,
    });

    // Enhanced text objects
    try registry.register(.{
        .name = "select_paragraph_around",
        .description = "Select paragraph (around - ap)",
        .handler = selectParagraphAround,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_paragraph_inside",
        .description = "Select paragraph (inside - ip)",
        .handler = selectParagraphInside,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_indent_around",
        .description = "Select indent level (around - ai)",
        .handler = selectIndentAround,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_indent_inside",
        .description = "Select indent level (inside - ii)",
        .handler = selectIndentInside,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_line_around",
        .description = "Select line (around - al)",
        .handler = selectLineAround,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_line_inside",
        .description = "Select line (inside - il)",
        .handler = selectLineInside,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_buffer_around",
        .description = "Select entire buffer (around - ab)",
        .handler = selectBufferAround,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_buffer_inside",
        .description = "Select entire buffer (inside - ib)",
        .handler = selectBufferInside,
        .category = .selection,
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

    // Word text object commands
    try registry.register(.{
        .name = "select_word",
        .description = "Select word under cursor (iw)",
        .handler = selectCurrentWord,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_all",
        .description = "Select all text in buffer (Ctrl+A)",
        .handler = selectAll,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_line",
        .description = "Select entire current line (V)",
        .handler = selectLine,
        .category = .selection,
    });

    try registry.register(.{
        .name = "extend_to_line_end",
        .description = "Extend selection to end of line (Shift+End)",
        .handler = extendToLineEnd,
        .category = .selection,
    });

    try registry.register(.{
        .name = "delete_word_object",
        .description = "Delete word under cursor (diw)",
        .handler = deleteCurrentWord,
        .category = .edit,
    });

    try registry.register(.{
        .name = "change_word",
        .description = "Change word under cursor (ciw)",
        .handler = changeCurrentWord,
        .category = .edit,
    });

    try registry.register(.{
        .name = "uppercase",
        .description = "Convert selection to uppercase (U or gU)",
        .handler = uppercaseSelection,
        .category = .edit,
    });

    try registry.register(.{
        .name = "lowercase",
        .description = "Convert selection to lowercase (u or gu)",
        .handler = lowercaseSelection,
        .category = .edit,
    });

    try registry.register(.{
        .name = "titlecase",
        .description = "Convert selection to title case (gt)",
        .handler = titlecaseSelection,
        .category = .edit,
    });

    // Pair text objects
    try registry.register(.{
        .name = "select_inner_paren",
        .description = "Select inside parentheses (vi()",
        .handler = selectInnerParen,
        .category = .selection,
    });

    try registry.register(.{
        .name = "delete_inner_paren",
        .description = "Delete inside parentheses (di()",
        .handler = deleteInnerParen,
        .category = .edit,
    });

    try registry.register(.{
        .name = "change_inner_paren",
        .description = "Change inside parentheses (ci()",
        .handler = changeInnerParen,
        .category = .edit,
    });

    try registry.register(.{
        .name = "select_inner_quote",
        .description = "Select inside double quotes (vi\")",
        .handler = selectInnerQuote,
        .category = .selection,
    });

    try registry.register(.{
        .name = "select_inner_bracket",
        .description = "Select inside brackets (vi[)",
        .handler = selectInnerBracket,
        .category = .selection,
    });

    try registry.register(.{
        .name = "delete_inner_bracket",
        .description = "Delete inside brackets (di[)",
        .handler = deleteInnerBracket,
        .category = .edit,
    });

    try registry.register(.{
        .name = "select_inner_brace",
        .description = "Select inside braces (vi{)",
        .handler = selectInnerBrace,
        .category = .selection,
    });

    try registry.register(.{
        .name = "delete_inner_brace",
        .description = "Delete inside braces (di{)",
        .handler = deleteInnerBrace,
        .category = .edit,
    });

    try registry.register(.{
        .name = "change_inner_brace",
        .description = "Change inside braces (ci{)",
        .handler = changeInnerBrace,
        .category = .edit,
    });

    // Mark commands
    try registry.register(.{
        .name = "set_mark",
        .description = "Set mark at cursor position (m)",
        .handler = setMark,
        .category = .motion,
    });

    try registry.register(.{
        .name = "jump_to_mark",
        .description = "Jump to mark (')",
        .handler = jumpToMark,
        .category = .motion,
    });

    try registry.register(.{
        .name = "list_marks",
        .description = "List all marks (:marks)",
        .handler = listMarks,
        .category = .motion,
    });

    // Paragraph navigation
    try registry.register(.{
        .name = "move_next_paragraph",
        .description = "Move to next paragraph (})",
        .handler = moveToNextParagraph,
        .category = .motion,
    });

    try registry.register(.{
        .name = "move_prev_paragraph",
        .description = "Move to previous paragraph ({)",
        .handler = moveToPrevParagraph,
        .category = .motion,
    });

    // Repeat command
    try registry.register(.{
        .name = "repeat_last_action",
        .description = "Repeat last action (dot command: .)",
        .handler = repeatLastAction,
        .category = .edit,
    });

    // Transpose commands
    try registry.register(.{
        .name = "transpose_chars",
        .description = "Transpose characters (Ctrl+T)",
        .handler = transposeCharacters,
        .category = .edit,
    });

    try registry.register(.{
        .name = "transpose_lines",
        .description = "Transpose current line with previous",
        .handler = transposeLines,
        .category = .edit,
    });

    // Line filtering commands
    try registry.register(.{
        .name = "sort_lines",
        .description = "Sort selected lines alphabetically",
        .handler = sortLines,
        .category = .edit,
    });

    try registry.register(.{
        .name = "unique_lines",
        .description = "Remove duplicate lines from selection",
        .handler = uniqueLines,
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

    try registry.register(.{
        .name = "move_line_up",
        .description = "Move current line up (Alt+Up)",
        .handler = moveLineUp,
        .category = .edit,
    });

    try registry.register(.{
        .name = "move_line_down",
        .description = "Move current line down (Alt+Down)",
        .handler = moveLineDown,
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
        .description = "Toggle file finder (Space F)",
        .handler = toggleFileFinder,
        .category = .system,
    });

    // Buffer switcher
    try registry.register(.{
        .name = "toggle_buffer_switcher",
        .description = "Toggle buffer switcher (Space B)",
        .handler = toggleBufferSwitcher,
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

    try registry.register(.{
        .name = "save_all",
        .description = "Save all modified buffers",
        .handler = saveAllBuffers,
        .category = .file,
    });

    try registry.register(.{
        .name = "close_buffer",
        .description = "Close current buffer (warns if modified)",
        .handler = closeCurrentBuffer,
        .category = .file,
    });

    try registry.register(.{
        .name = "force_close_buffer",
        .description = "Force close buffer without saving",
        .handler = forceCloseBuffer,
        .category = .file,
    });

    // Configuration commands
    try registry.register(.{
        .name = "config_write",
        .description = "Write configuration to file (~/.config/aesop/config.conf)",
        .handler = configWrite,
        .category = .system,
    });

    try registry.register(.{
        .name = "config_show",
        .description = "Show current configuration settings",
        .handler = configShow,
        .category = .system,
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

    try registry.register(.{
        .name = "replace_next",
        .description = "Replace next occurrence",
        .handler = replaceNext,
        .category = .search,
    });

    try registry.register(.{
        .name = "replace_all",
        .description = "Replace all occurrences",
        .handler = replaceAll,
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
        .name = "goto_line",
        .description = "Jump to specific line number (:goto or Ctrl+G)",
        .handler = gotoLine,
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

    try registry.register(.{
        .name = "scroll_page_up",
        .description = "Scroll viewport up by one page (Page Up)",
        .handler = scrollPageUp,
        .category = .view,
    });

    try registry.register(.{
        .name = "scroll_page_down",
        .description = "Scroll viewport down by one page (Page Down)",
        .handler = scrollPageDown,
        .category = .view,
    });

    try registry.register(.{
        .name = "scroll_half_page_up",
        .description = "Scroll viewport up by half page (Ctrl+U)",
        .handler = scrollHalfPageUp,
        .category = .view,
    });

    try registry.register(.{
        .name = "scroll_half_page_down",
        .description = "Scroll viewport down by half page (Ctrl+D)",
        .handler = scrollHalfPageDown,
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

    // Macro commands
    try registry.register(.{
        .name = "start_macro_recording",
        .description = "Start recording macro (q)",
        .handler = startMacroRecording,
        .category = .system,
    });

    try registry.register(.{
        .name = "stop_macro_recording",
        .description = "Stop recording macro (q when recording)",
        .handler = stopMacroRecording,
        .category = .system,
    });

    try registry.register(.{
        .name = "play_macro",
        .description = "Play macro from register (@)",
        .handler = playMacro,
        .category = .system,
    });

    // LSP commands
    try registry.register(.{
        .name = "lsp_trigger_completion",
        .description = "Trigger code completion (Ctrl+Space)",
        .handler = lspTriggerCompletion,
        .category = .system,
    });

    try registry.register(.{
        .name = "lsp_hide_completion",
        .description = "Hide completion list (Esc)",
        .handler = lspHideCompletion,
        .category = .system,
    });

    try registry.register(.{
        .name = "lsp_completion_previous",
        .description = "Select previous completion item",
        .handler = lspCompletionPrevious,
        .category = .system,
    });

    try registry.register(.{
        .name = "lsp_completion_next",
        .description = "Select next completion item",
        .handler = lspCompletionNext,
        .category = .system,
    });

    try registry.register(.{
        .name = "lsp_accept_completion",
        .description = "Accept selected completion (Enter/Tab)",
        .handler = lspAcceptCompletion,
        .category = .system,
    });

    try registry.register(.{
        .name = "lsp_goto_definition",
        .description = "Go to definition of symbol under cursor (gd)",
        .handler = lspGotoDefinition,
        .category = .system,
    });

    try registry.register(.{
        .name = "lsp_show_hover",
        .description = "Show hover information for symbol (K)",
        .handler = lspShowHover,
        .category = .system,
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
