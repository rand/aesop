//! Command line parser for ex-style commands
//! Parses commands like :q, :w, :wq, :e, etc.

const std = @import("std");

/// Parsed command
pub const Command = union(enum) {
    quit: struct { force: bool = false },
    write: struct { path: ?[]const u8 = null },
    write_quit: struct { force: bool = false, path: ?[]const u8 = null },
    edit: struct { path: []const u8 },
    unknown: []const u8,

    /// Check if command should quit editor
    pub fn shouldQuit(self: Command) bool {
        return switch (self) {
            .quit, .write_quit => true,
            else => false,
        };
    }

    /// Check if command should save
    pub fn shouldWrite(self: Command) bool {
        return switch (self) {
            .write, .write_quit => true,
            else => false,
        };
    }
};

/// Parse a command line string (without the leading ':')
pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Command {
    // Trim whitespace
    const trimmed = std.mem.trim(u8, input, &std.ascii.whitespace);
    if (trimmed.len == 0) return Command{ .unknown = "" };

    // Check for force modifier (!)
    const has_force = std.mem.endsWith(u8, trimmed, "!");
    const cmd_text = if (has_force)
        trimmed[0 .. trimmed.len - 1]
    else
        trimmed;

    // Split command and arguments
    var parts = std.mem.splitScalar(u8, cmd_text, ' ');
    const cmd = parts.first();
    const args = parts.rest();

    // Parse commands
    if (std.mem.eql(u8, cmd, "q") or std.mem.eql(u8, cmd, "quit")) {
        return Command{ .quit = .{ .force = has_force } };
    } else if (std.mem.eql(u8, cmd, "w") or std.mem.eql(u8, cmd, "write")) {
        const path = if (args.len > 0) try allocator.dupe(u8, std.mem.trim(u8, args, &std.ascii.whitespace)) else null;
        return Command{ .write = .{ .path = path } };
    } else if (std.mem.eql(u8, cmd, "wq") or std.mem.eql(u8, cmd, "x")) {
        const path = if (args.len > 0) try allocator.dupe(u8, std.mem.trim(u8, args, &std.ascii.whitespace)) else null;
        return Command{ .write_quit = .{ .force = has_force, .path = path } };
    } else if (std.mem.eql(u8, cmd, "e") or std.mem.eql(u8, cmd, "edit")) {
        if (args.len == 0) return Command{ .unknown = cmd_text };
        return Command{ .edit = .{ .path = try allocator.dupe(u8, std.mem.trim(u8, args, &std.ascii.whitespace)) } };
    }

    // Unknown command
    return Command{ .unknown = try allocator.dupe(u8, cmd_text) };
}

/// Free any allocated memory in the command
pub fn deinit(cmd: Command, allocator: std.mem.Allocator) void {
    switch (cmd) {
        .write => |w| if (w.path) |p| allocator.free(p),
        .write_quit => |wq| if (wq.path) |p| allocator.free(p),
        .edit => |e| allocator.free(e.path),
        .unknown => |u| if (u.len > 0) allocator.free(u),
        else => {},
    }
}

// === Tests ===

test "parse: quit" {
    const allocator = std.testing.allocator;

    const cmd1 = try parse(allocator, "q");
    defer deinit(cmd1, allocator);
    try std.testing.expect(cmd1 == .quit);
    try std.testing.expect(!cmd1.quit.force);

    const cmd2 = try parse(allocator, "quit");
    defer deinit(cmd2, allocator);
    try std.testing.expect(cmd2 == .quit);

    const cmd3 = try parse(allocator, "q!");
    defer deinit(cmd3, allocator);
    try std.testing.expect(cmd3 == .quit);
    try std.testing.expect(cmd3.quit.force);
}

test "parse: write" {
    const allocator = std.testing.allocator;

    const cmd1 = try parse(allocator, "w");
    defer deinit(cmd1, allocator);
    try std.testing.expect(cmd1 == .write);
    try std.testing.expect(cmd1.write.path == null);

    const cmd2 = try parse(allocator, "w test.txt");
    defer deinit(cmd2, allocator);
    try std.testing.expect(cmd2 == .write);
    try std.testing.expectEqualStrings("test.txt", cmd2.write.path.?);
}

test "parse: write-quit" {
    const allocator = std.testing.allocator;

    const cmd1 = try parse(allocator, "wq");
    defer deinit(cmd1, allocator);
    try std.testing.expect(cmd1 == .write_quit);
    try std.testing.expect(!cmd1.write_quit.force);

    const cmd2 = try parse(allocator, "wq!");
    defer deinit(cmd2, allocator);
    try std.testing.expect(cmd2 == .write_quit);
    try std.testing.expect(cmd2.write_quit.force);

    const cmd3 = try parse(allocator, "x");
    defer deinit(cmd3, allocator);
    try std.testing.expect(cmd3 == .write_quit);
}

test "parse: edit" {
    const allocator = std.testing.allocator;

    const cmd = try parse(allocator, "e newfile.txt");
    defer deinit(cmd, allocator);
    try std.testing.expect(cmd == .edit);
    try std.testing.expectEqualStrings("newfile.txt", cmd.edit.path);
}

test "parse: unknown" {
    const allocator = std.testing.allocator;

    const cmd = try parse(allocator, "foobar");
    defer deinit(cmd, allocator);
    try std.testing.expect(cmd == .unknown);
}

test "parse: whitespace handling" {
    const allocator = std.testing.allocator;

    const cmd1 = try parse(allocator, "  q  ");
    defer deinit(cmd1, allocator);
    try std.testing.expect(cmd1 == .quit);

    const cmd2 = try parse(allocator, "w   file.txt   ");
    defer deinit(cmd2, allocator);
    try std.testing.expect(cmd2 == .write);
    try std.testing.expectEqualStrings("file.txt", cmd2.write.path.?);
}

test "command: shouldQuit" {
    const allocator = std.testing.allocator;

    const cmd1 = try parse(allocator, "q");
    defer deinit(cmd1, allocator);
    try std.testing.expect(cmd1.shouldQuit());

    const cmd2 = try parse(allocator, "wq");
    defer deinit(cmd2, allocator);
    try std.testing.expect(cmd2.shouldQuit());

    const cmd3 = try parse(allocator, "w");
    defer deinit(cmd3, allocator);
    try std.testing.expect(!cmd3.shouldQuit());
}

test "command: shouldWrite" {
    const allocator = std.testing.allocator;

    const cmd1 = try parse(allocator, "w");
    defer deinit(cmd1, allocator);
    try std.testing.expect(cmd1.shouldWrite());

    const cmd2 = try parse(allocator, "wq");
    defer deinit(cmd2, allocator);
    try std.testing.expect(cmd2.shouldWrite());

    const cmd3 = try parse(allocator, "q");
    defer deinit(cmd3, allocator);
    try std.testing.expect(!cmd3.shouldWrite());
}
