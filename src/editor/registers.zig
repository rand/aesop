//! Register system for named clipboards
//! Supports vim-style registers: a-z, 0-9, unnamed, system, black hole

const std = @import("std");

/// Register identifier
pub const RegisterId = union(enum) {
    named: u8,        // a-z: 26 named registers
    numbered: u8,     // 0-9: history registers (0 is most recent yank)
    unnamed,          // "": default register
    system,           // +: system clipboard
    black_hole,       // _: delete without saving

    pub fn fromChar(ch: u8) ?RegisterId {
        if (ch >= 'a' and ch <= 'z') {
            return .{ .named = ch };
        }
        if (ch >= '0' and ch <= '9') {
            return .{ .numbered = ch - '0' };
        }
        return switch (ch) {
            '"' => .unnamed,
            '+', '*' => .system,
            '_' => .black_hole,
            else => null,
        };
    }

    pub fn toChar(self: RegisterId) u8 {
        return switch (self) {
            .named => |ch| ch,
            .numbered => |n| '0' + n,
            .unnamed => '"',
            .system => '+',
            .black_hole => '_',
        };
    }
};

/// Register content
pub const RegisterContent = struct {
    text: []const u8,
    is_linewise: bool = false, // If true, paste as complete lines

    pub fn deinit(self: *RegisterContent, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

/// Register manager
pub const RegisterManager = struct {
    named_registers: [26]?RegisterContent = [_]?RegisterContent{null} ** 26,
    numbered_registers: [10]?RegisterContent = [_]?RegisterContent{null} ** 10,
    unnamed_register: ?RegisterContent = null,
    system_register: ?RegisterContent = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RegisterManager {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RegisterManager) void {
        // Free named registers
        for (&self.named_registers) |*reg| {
            if (reg.*) |*content| {
                content.deinit(self.allocator);
            }
        }

        // Free numbered registers
        for (&self.numbered_registers) |*reg| {
            if (reg.*) |*content| {
                content.deinit(self.allocator);
            }
        }

        // Free unnamed register
        if (self.unnamed_register) |*content| {
            content.deinit(self.allocator);
        }

        // Free system register
        if (self.system_register) |*content| {
            content.deinit(self.allocator);
        }
    }

    /// Set register content
    pub fn set(self: *RegisterManager, id: RegisterId, text: []const u8, linewise: bool) !void {
        // Black hole register discards content
        if (std.meta.eql(id, RegisterId.black_hole)) {
            return;
        }

        const content = RegisterContent{
            .text = try self.allocator.dupe(u8, text),
            .is_linewise = linewise,
        };

        switch (id) {
            .named => |ch| {
                const idx = ch - 'a';
                if (self.named_registers[idx]) |*old| {
                    old.deinit(self.allocator);
                }
                self.named_registers[idx] = content;
            },
            .numbered => |n| {
                if (self.numbered_registers[n]) |*old| {
                    old.deinit(self.allocator);
                }
                self.numbered_registers[n] = content;
            },
            .unnamed => {
                if (self.unnamed_register) |*old| {
                    old.deinit(self.allocator);
                }
                self.unnamed_register = content;
            },
            .system => {
                if (self.system_register) |*old| {
                    old.deinit(self.allocator);
                }
                self.system_register = content;
                // TODO: Actually copy to system clipboard
            },
            .black_hole => unreachable,
        }
    }

    /// Get register content (returns reference, caller must not free)
    pub fn get(self: *const RegisterManager, id: RegisterId) ?*const RegisterContent {
        return switch (id) {
            .named => |ch| blk: {
                const idx = ch - 'a';
                if (self.named_registers[idx]) |*content| {
                    break :blk content;
                }
                break :blk null;
            },
            .numbered => |n| blk: {
                if (self.numbered_registers[n]) |*content| {
                    break :blk content;
                }
                break :blk null;
            },
            .unnamed => if (self.unnamed_register) |*content| content else null,
            .system => if (self.system_register) |*content| content else null,
            .black_hole => null,
        };
    }

    /// Set content and update history (for yank operations)
    pub fn yank(self: *RegisterManager, text: []const u8, linewise: bool, target: ?RegisterId) !void {
        const register = target orelse RegisterId.unnamed;

        // Set the target register
        try self.set(register, text, linewise);

        // Also set unnamed register if we're yanking to a named register
        if (target) |reg| {
            switch (reg) {
                .named => try self.set(.unnamed, text, linewise),
                else => {},
            }
        }

        // Shift numbered registers (0 becomes 1, 1 becomes 2, etc.)
        // This creates a yank history
        var i: usize = 9;
        while (i > 0) : (i -= 1) {
            if (self.numbered_registers[i - 1]) |old_content| {
                if (self.numbered_registers[i]) |*to_free| {
                    to_free.deinit(self.allocator);
                }
                self.numbered_registers[i] = RegisterContent{
                    .text = try self.allocator.dupe(u8, old_content.text),
                    .is_linewise = old_content.is_linewise,
                };
            }
        }

        // Set register 0 to the yanked text
        try self.set(.{ .numbered = 0 }, text, linewise);
    }

    /// Get default register for operations (unnamed or 0)
    pub fn getDefault(self: *const RegisterManager) ?*const RegisterContent {
        if (self.unnamed_register) |*content| {
            return content;
        }
        if (self.numbered_registers[0]) |*content| {
            return content;
        }
        return null;
    }

    /// List all non-empty registers
    pub fn listRegisters(self: *const RegisterManager, allocator: std.mem.Allocator) ![]RegisterInfo {
        var list = std.ArrayList(RegisterInfo).empty;
        defer list.deinit(allocator);

        // Named registers
        for (self.named_registers, 0..) |maybe_content, i| {
            if (maybe_content) |content| {
                const ch: u8 = @intCast('a' + i);
                try list.append(allocator, .{
                    .id = .{ .named = ch },
                    .preview = try getPreview(allocator, content.text),
                    .linewise = content.is_linewise,
                });
            }
        }

        // Numbered registers
        for (self.numbered_registers, 0..) |maybe_content, i| {
            if (maybe_content) |content| {
                const n: u8 = @intCast(i);
                try list.append(allocator, .{
                    .id = .{ .numbered = n },
                    .preview = try getPreview(allocator, content.text),
                    .linewise = content.is_linewise,
                });
            }
        }

        // Unnamed register
        if (self.unnamed_register) |content| {
            try list.append(allocator, .{
                .id = .unnamed,
                .preview = try getPreview(allocator, content.text),
                .linewise = content.is_linewise,
            });
        }

        return list.toOwnedSlice(allocator);
    }

    fn getPreview(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        // Return first 50 chars, replacing newlines with ↵
        const max_len = @min(text.len, 50);
        var preview = std.ArrayList(u8).empty;
        defer preview.deinit(allocator);

        for (text[0..max_len]) |ch| {
            if (ch == '\n') {
                try preview.appendSlice(allocator, "↵");
            } else {
                try preview.append(allocator, ch);
            }
        }

        if (text.len > 50) {
            try preview.appendSlice(allocator, "...");
        }

        return preview.toOwnedSlice(allocator);
    }
};

/// Register info for listing
pub const RegisterInfo = struct {
    id: RegisterId,
    preview: []const u8,
    linewise: bool,

    pub fn deinit(self: *RegisterInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.preview);
    }
};

// === Tests ===

test "registers: basic set and get" {
    const allocator = std.testing.allocator;
    var mgr = RegisterManager.init(allocator);
    defer mgr.deinit();

    try mgr.set(.{ .named = 'a' }, "hello", false);

    const content = mgr.get(.{ .named = 'a' });
    try std.testing.expect(content != null);
    try std.testing.expect(std.mem.eql(u8, content.?.text, "hello"));
}

test "registers: yank history" {
    const allocator = std.testing.allocator;
    var mgr = RegisterManager.init(allocator);
    defer mgr.deinit();

    try mgr.yank("first", false, null);
    try mgr.yank("second", false, null);
    try mgr.yank("third", false, null);

    const reg0 = mgr.get(.{ .numbered = 0 });
    const reg1 = mgr.get(.{ .numbered = 1 });
    const reg2 = mgr.get(.{ .numbered = 2 });

    try std.testing.expect(std.mem.eql(u8, reg0.?.text, "third"));
    try std.testing.expect(std.mem.eql(u8, reg1.?.text, "second"));
    try std.testing.expect(std.mem.eql(u8, reg2.?.text, "first"));
}

test "registers: black hole" {
    const allocator = std.testing.allocator;
    var mgr = RegisterManager.init(allocator);
    defer mgr.deinit();

    try mgr.set(.black_hole, "discarded", false);

    const content = mgr.get(.black_hole);
    try std.testing.expect(content == null);
}
