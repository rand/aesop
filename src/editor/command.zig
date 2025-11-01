//! Command registry and execution system
//! Composable commands for modal editing

const std = @import("std");

/// Command context - passed to command handlers
pub const Context = struct {
    // Placeholder - will be filled with editor state
    // This will include: buffers, selections, mode, etc.
    user_data: ?*anyopaque = null,
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

// === Built-in command handlers (placeholders) ===

fn moveLeft(ctx: *Context) Result {
    _ = ctx;
    return Result.ok();
}

fn moveRight(ctx: *Context) Result {
    _ = ctx;
    return Result.ok();
}

fn moveUp(ctx: *Context) Result {
    _ = ctx;
    return Result.ok();
}

fn moveDown(ctx: *Context) Result {
    _ = ctx;
    return Result.ok();
}

fn insertMode(ctx: *Context) Result {
    _ = ctx;
    return Result.ok();
}

fn normalMode(ctx: *Context) Result {
    _ = ctx;
    return Result.ok();
}

/// Register all built-in commands
pub fn registerBuiltins(registry: *Registry) !void {
    // Motion commands
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

    // Mode commands
    try registry.register(.{
        .name = "insert_mode",
        .description = "Enter insert mode",
        .handler = insertMode,
        .category = .mode,
    });

    try registry.register(.{
        .name = "normal_mode",
        .description = "Enter normal mode",
        .handler = normalMode,
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
