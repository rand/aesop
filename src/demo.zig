//! Hello World rendering demo
//! Demonstrates the terminal rendering pipeline

const std = @import("std");
const renderer_mod = @import("render/renderer.zig");
const input_mod = @import("terminal/input.zig");
const platform = @import("terminal/platform.zig");

const Renderer = renderer_mod.Renderer;
const Color = renderer_mod.Color;
const Attrs = renderer_mod.Attrs;

pub fn runDemo(allocator: std.mem.Allocator) !void {
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();

    // Enter raw mode
    try renderer.enterRawMode();
    defer renderer.exitRawMode() catch {};

    // Get terminal size
    const size = renderer.getSize();

    // Draw welcome screen
    try drawWelcome(&renderer, size.width, size.height);
    try renderer.render();

    // Wait for keypress
    var input_buf: [64]u8 = undefined;
    var parser = input_mod.Parser{};

    while (true) {
        const n = try renderer.terminal.readInput(&input_buf);
        if (n > 0) {
            const events = try parser.parse(allocator, input_buf[0..n]);
            defer allocator.free(events);

            for (events) |event| {
                switch (event) {
                    .char => |c| {
                        // Exit on 'q' or Ctrl+C
                        if (c.codepoint == 'q' or (c.codepoint == 'c' and c.mods.ctrl)) {
                            return;
                        }
                    },
                    .key => |k| {
                        // Exit on Escape
                        if (k.key == .escape) {
                            return;
                        }
                    },
                    else => {},
                }
            }
        }

        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
}

fn drawWelcome(renderer: *Renderer, width: u16, height: u16) !void {
    renderer.clear();

    const title = "AESOP TEXT EDITOR";
    const subtitle = "High-Performance Modal Editing in Zig";
    const version = "v0.0.1 - Phase 1 Foundation";

    // Colors
    const title_fg = Color{ .rgb = .{ .r = 152, .g = 195, .b = 121 } }; // Green
    const subtitle_fg = Color{ .rgb = .{ .r = 97, .g = 175, .b = 239 } }; // Blue
    const info_fg = Color{ .standard = .bright_black };

    // Center title
    const title_row = height / 2 - 5;
    const title_col = (width - title.len) / 2;
    renderer.writeText(@intCast(title_row), @intCast(title_col), title, title_fg, .default, .{ .bold = true }, null);

    // Center subtitle
    const subtitle_row = title_row + 2;
    const subtitle_col = (width - subtitle.len) / 2;
    renderer.writeText(@intCast(subtitle_row), @intCast(subtitle_col), subtitle, subtitle_fg, .default, .{}, null);

    // Center version
    const version_row = subtitle_row + 1;
    const version_col = (width - version.len) / 2;
    renderer.writeText(@intCast(version_row), @intCast(version_col), version, info_fg, .default, .{}, null);

    // Feature list
    const features = [_][]const u8{
        "✓ Terminal Abstraction (VT100/xterm)",
        "✓ Rope Data Structure (UTF-8 aware)",
        "✓ Input Event Parser (keyboard, mouse)",
        "✓ Damage-Tracked Rendering",
        "✓ Direct Escape Sequence Control",
        "✓ zio Async I/O Integration",
    };

    const feature_start_row = version_row + 3;
    for (features, 0..) |feature, i| {
        const row = feature_start_row + i;
        const col = (width - feature.len) / 2;
        const fg = Color{ .standard = .bright_green };
        renderer.writeText(@intCast(row), @intCast(col), feature, fg, .default, .{}, null);
    }

    // Instructions
    const instructions = [_][]const u8{
        "Press 'q' or ESC to exit",
        "Press any other key to continue",
    };

    const instr_row = feature_start_row + features.len + 3;
    for (instructions, 0..) |instr, i| {
        const row = instr_row + i;
        const col = (width - instr.len) / 2;
        renderer.writeText(@intCast(row), @intCast(col), instr, info_fg, .default, .{ .dim = true }, null);
    }

    // Footer
    const footer = "🤖 Built with Zig 0.15.1 | Powered by zio v0.4.0";
    const footer_row = height - 2;
    const footer_col = (width - footer.len) / 2;
    renderer.writeText(@intCast(footer_row), @intCast(footer_col), footer, info_fg, .default, .{ .dim = true }, null);
}
