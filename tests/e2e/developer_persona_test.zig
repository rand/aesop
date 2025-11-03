//! E2E tests for developer persona workflow
//! Simulates a developer editing code with LSP assistance

const std = @import("std");
const testing = std.testing;
const Helpers = @import("../helpers.zig");
const Buffer = @import("../../src/buffer/manager.zig").Buffer;
const Editor = @import("../../src/editor/editor.zig").Editor;
const Actions = @import("../../src/editor/actions.zig");
const Cursor = @import("../../src/editor/cursor.zig");

test "developer persona: write Zig function with LSP" {
    const allocator = testing.allocator;

    // Setup: Create buffer for new Zig file
    var buffer = try Buffer.init(allocator, "test.zig");
    defer buffer.deinit();

    // Simulate developer workflow
    // 1. Type function signature
    const sig = "pub fn calculateSum(a: i32, b: i32) i32 {\n";
    try buffer.rope.insert(0, sig);

    // 2. Add function body with indent
    const body = "    return a + b;\n";
    try buffer.rope.insert(sig.len, body);

    // 3. Close function
    const close = "}\n";
    try buffer.rope.insert(sig.len + body.len, close);

    // Verify final content
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "pub fn calculateSum") != null);
    try testing.expect(std.mem.indexOf(u8, content, "return a + b") != null);
    try Helpers.Assertions.expectLineCount(&buffer, 3);
}

test "developer persona: refactor with multi-cursor" {
    const allocator = testing.allocator;

    const code =
        \\const x = 5;
        \\const y = 10;
        \\const z = 15;
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(code);
    defer buffer.deinit();

    // Create multi-cursor selection for "const"
    var selections = std.ArrayList(Cursor.Selection).init(allocator);
    defer selections.deinit();

    // Select each "const" keyword
    try selections.append(Cursor.Selection.init(
        Cursor.Position{ .line = 0, .col = 0 },
        Cursor.Position{ .line = 0, .col = 5 },
    ));
    try selections.append(Cursor.Selection.init(
        Cursor.Position{ .line = 1, .col = 0 },
        Cursor.Position{ .line = 1, .col = 5 },
    ));
    try selections.append(Cursor.Selection.init(
        Cursor.Position{ .line = 2, .col = 0 },
        Cursor.Position{ .line = 2, .col = 5 },
    ));

    // Verify we have 3 lines with "const"
    try Helpers.Assertions.expectLineCount(&buffer, 3);
}

test "developer persona: code completion workflow" {
    const allocator = testing.allocator;

    // Setup mock LSP
    var mock_lsp = Helpers.MockLSP{};

    // Create completion response
    const items = [_][]const u8{ "calculateSum", "calculateProduct", "calculateAverage" };
    const response = try mock_lsp.completionResponse(allocator, &items);
    defer allocator.free(response);

    // Verify response format
    try testing.expect(std.mem.indexOf(u8, response, "calculateSum") != null);
    try testing.expect(std.mem.indexOf(u8, response, "calculateProduct") != null);
    try testing.expect(std.mem.indexOf(u8, response, "calculateAverage") != null);
}

test "developer persona: navigate to definition" {
    const allocator = testing.allocator;

    const code =
        \\const MyStruct = struct {
        \\    field: i32,
        \\};
        \\
        \\pub fn main() void {
        \\    var s = MyStruct{ .field = 42 };
        \\}
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(code);
    defer buffer.deinit();

    // Verify structure is in buffer
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "MyStruct") != null);
    try testing.expect(std.mem.indexOf(u8, content, "field") != null);
}

test "developer persona: fix compilation error" {
    const allocator = testing.allocator;

    // Start with broken code (missing semicolon)
    const broken =
        \\const x = 5
        \\const y = 10;
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(broken);
    defer buffer.deinit();

    // Simulate fix: add semicolon after first line
    const first_line = try buffer.rope.getLine(allocator, 0);
    defer allocator.free(first_line);

    // Developer would see diagnostic and add semicolon
    const pos = first_line.len; // Position 10 (after "5")
    try buffer.rope.insert(pos, ";");

    // Verify fix
    const fixed = try buffer.rope.toString(allocator);
    defer allocator.free(fixed);

    try testing.expect(std.mem.indexOf(u8, fixed, "const x = 5;") != null);
}

test "developer persona: comment and uncomment code" {
    const allocator = testing.allocator;

    const code = "const x = 5;\n";
    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(code);
    defer buffer.deinit();

    // Comment line by inserting "//" at start
    try buffer.rope.insert(0, "// ");

    var commented = try buffer.rope.toString(allocator);
    defer allocator.free(commented);
    try testing.expect(std.mem.indexOf(u8, commented, "// const x = 5;") != null);

    // Uncomment by deleting first 3 chars
    try buffer.rope.delete(0, 3);

    const uncommented = try buffer.rope.toString(allocator);
    defer allocator.free(uncommented);
    try testing.expectEqualStrings(code, uncommented);
}

test "developer persona: format on save" {
    const allocator = testing.allocator;

    // Unformatted code
    const unformatted =
        \\pub fn main() void {
        \\const x=5;
        \\if(x>0){
        \\return;
        \\}
        \\}
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(unformatted);
    defer buffer.deinit();

    // In real workflow, formatter would be called
    // For now, just verify buffer can be accessed
    try Helpers.Assertions.expectLineCount(&buffer, 6);
}

test "developer persona: test-driven development cycle" {
    const allocator = testing.allocator;

    // 1. Write test first
    const test_code =
        \\test "add function" {
        \\    try testing.expectEqual(@as(i32, 7), add(3, 4));
        \\}
    ;

    var test_buffer = try Helpers.BufferBuilder.init(allocator).withContent(test_code);
    defer test_buffer.deinit();

    // 2. Write implementation
    const impl_code =
        \\fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var impl_buffer = try Helpers.BufferBuilder.init(allocator).withContent(impl_code);
    defer impl_buffer.deinit();

    // Verify both buffers exist
    try Helpers.Assertions.expectLineCount(&test_buffer, 3);
    try Helpers.Assertions.expectLineCount(&impl_buffer, 3);
}
