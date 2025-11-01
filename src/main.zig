const std = @import("std");
const zio = @import("zio");
const demo = @import("demo.zig");
const editor_app = @import("editor_app.zig");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.skip();

    // Check for --demo flag
    var run_demo = false;
    var filepath: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--demo")) {
            run_demo = true;
        } else {
            filepath = arg;
        }
    }

    if (run_demo) {
        // Run hello world demo
        try demo.runDemo(allocator);
    } else {
        // Run the editor
        try editor_app.runEditor(allocator, filepath);
    }
}

test "basic editor startup" {
    try std.testing.expect(true);
}
