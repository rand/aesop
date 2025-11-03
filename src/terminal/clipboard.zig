//! System clipboard integration
//! Provides cross-platform clipboard access using external commands

const std = @import("std");
const builtin = @import("builtin");

/// Clipboard error types
pub const ClipboardError = error{
    CopyFailed,
    PasteFailed,
    UnsupportedPlatform,
    CommandNotFound,
    OutOfMemory,
};

/// Copy text to system clipboard
pub fn copy(allocator: std.mem.Allocator, text: []const u8) !void {
    switch (builtin.os.tag) {
        .macos => try copyMacOS(allocator, text),
        .linux => try copyLinux(allocator, text),
        .windows => return ClipboardError.UnsupportedPlatform, // TODO: Windows support
        else => return ClipboardError.UnsupportedPlatform,
    }
}

/// Paste text from system clipboard
pub fn paste(allocator: std.mem.Allocator) ![]u8 {
    return switch (builtin.os.tag) {
        .macos => try pasteMacOS(allocator),
        .linux => try pasteLinux(allocator),
        .windows => ClipboardError.UnsupportedPlatform, // TODO: Windows support
        else => ClipboardError.UnsupportedPlatform,
    };
}

/// Copy to clipboard on macOS using pbcopy
fn copyMacOS(allocator: std.mem.Allocator, text: []const u8) !void {
    var child = std.process.Child.init(&[_][]const u8{"pbcopy"}, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    // Write text to pbcopy's stdin
    if (child.stdin) |stdin| {
        try stdin.writeAll(text);
        stdin.close();
        child.stdin = null;
    }

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) return ClipboardError.CopyFailed;
        },
        else => return ClipboardError.CopyFailed,
    }
}

/// Paste from clipboard on macOS using pbpaste
fn pasteMacOS(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&[_][]const u8{"pbpaste"}, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    // Read from pbpaste's stdout
    const stdout = child.stdout orelse return ClipboardError.PasteFailed;
    const content = try stdout.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    errdefer allocator.free(content);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(content);
                return ClipboardError.PasteFailed;
            }
        },
        else => {
            allocator.free(content);
            return ClipboardError.PasteFailed;
        },
    }

    return content;
}

/// Copy to clipboard on Linux using xclip or xsel
fn copyLinux(allocator: std.mem.Allocator, text: []const u8) !void {
    // Try xclip first, then xsel
    copyLinuxXclip(allocator, text) catch {
        try copyLinuxXsel(allocator, text);
    };
}

/// Copy using xclip
fn copyLinuxXclip(allocator: std.mem.Allocator, text: []const u8) !void {
    var child = std.process.Child.init(&[_][]const u8{ "xclip", "-selection", "clipboard" }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    if (child.stdin) |stdin| {
        try stdin.writeAll(text);
        stdin.close();
        child.stdin = null;
    }

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) return ClipboardError.CopyFailed;
        },
        else => return ClipboardError.CopyFailed,
    }
}

/// Copy using xsel
fn copyLinuxXsel(allocator: std.mem.Allocator, text: []const u8) !void {
    var child = std.process.Child.init(&[_][]const u8{ "xsel", "--clipboard", "--input" }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    if (child.stdin) |stdin| {
        try stdin.writeAll(text);
        stdin.close();
        child.stdin = null;
    }

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) return ClipboardError.CopyFailed;
        },
        else => return ClipboardError.CopyFailed,
    }
}

/// Paste from clipboard on Linux using xclip or xsel
fn pasteLinux(allocator: std.mem.Allocator) ![]u8 {
    // Try xclip first, then xsel
    return pasteLinuxXclip(allocator) catch {
        return try pasteLinuxXsel(allocator);
    };
}

/// Paste using xclip
fn pasteLinuxXclip(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&[_][]const u8{ "xclip", "-selection", "clipboard", "-out" }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = child.stdout orelse return ClipboardError.PasteFailed;
    const content = try stdout.readToEndAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(content);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(content);
                return ClipboardError.PasteFailed;
            }
        },
        else => {
            allocator.free(content);
            return ClipboardError.PasteFailed;
        },
    }

    return content;
}

/// Paste using xsel
fn pasteLinuxXsel(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&[_][]const u8{ "xsel", "--clipboard", "--output" }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = child.stdout orelse return ClipboardError.PasteFailed;
    const content = try stdout.readToEndAlloc(allocator, 10 * 1024 * 1024);
    errdefer allocator.free(content);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(content);
                return ClipboardError.PasteFailed;
            }
        },
        else => {
            allocator.free(content);
            return ClipboardError.PasteFailed;
        },
    }

    return content;
}
