const std = @import("std");
const zio = @import("zio");
const demo = @import("demo.zig");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Run hello world demo
    try demo.runDemo(allocator);
}

test "basic editor startup" {
    try std.testing.expect(true);
}
