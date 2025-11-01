const std = @import("std");
const zio = @import("zio");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Print startup message
    std.debug.print("Aesop Text Editor v0.0.1\n", .{});
    std.debug.print("Zig {s} | zio v0.4.0\n", .{@import("builtin").zig_version_string});
    std.debug.print("Phase 1: Foundation (in development)\n\n", .{});

    // TODO: Initialize terminal
    // TODO: Initialize editor state
    // TODO: Start rendering loop
    // TODO: Start IO thread with zio runtime

    _ = allocator; // Will be used soon
}

test "basic editor startup" {
    // Placeholder test
    try std.testing.expect(true);
}
