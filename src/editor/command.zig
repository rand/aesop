//! Command registry and execution system
//! Composable commands for modal editing

const std = @import("std");

// Forward declare Editor to avoid circular dependency
pub const Editor = @import("editor.zig").Editor;

/// Command context - passed to command handlers
pub const Context = struct {
    editor: *Editor,
};

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
const Buffer = @import("../buffer/manager.zig");

fn moveLeft(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveLeft(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveRight(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveRight(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveUp(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveUp(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveDown(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveDown(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveWordForward(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveWordForward(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveWordBackward(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveWordBackward(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveWordEnd(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveWordEnd(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveLineStart(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveLineStart(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveLineEnd(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveLineEnd(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveFileStart(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveFileStart(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

    return Result.ok();
}

fn moveFileEnd(ctx: *Context) Result {
    const buffer = ctx.editor.getActiveBuffer() orelse return Result.err("No active buffer");
    const primary_sel = ctx.editor.selections.primary(ctx.editor.allocator) orelse return Result.err("No selection");

    const new_sel = Motions.moveFileEnd(primary_sel, buffer);
    ctx.editor.selections.setSingleCursor(ctx.editor.allocator, new_sel.head) catch return Result.err("Failed to update selection");

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
