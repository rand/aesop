const std = @import("std");

/// Sample Zig file for testing tree-sitter parsing and highlighting
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Test comment
    const greeting = "Hello, World!";
    std.debug.print("{s}\n", .{greeting});

    const result = try calculate(allocator, 42);
    std.debug.print("Result: {d}\n", .{result});
}

/// Calculate something
fn calculate(allocator: std.mem.Allocator, value: i32) !i32 {
    _ = allocator;
    return value * 2;
}

test "basic test" {
    const result = try calculate(std.testing.allocator, 21);
    try std.testing.expectEqual(@as(i32, 42), result);
}
