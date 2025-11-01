//! Buffer manager - manages multiple text buffers
//! Handles buffer lifecycle, file I/O, and buffer switching

const std = @import("std");
const Rope = @import("rope.zig").Rope;

/// Buffer ID type
pub const BufferId = u32;

/// Buffer metadata
pub const BufferMetadata = struct {
    id: BufferId,
    filepath: ?[]const u8, // null for unsaved buffers
    modified: bool,
    readonly: bool,
    created_at: i64,
    modified_at: i64,

    pub fn init(id: BufferId, filepath: ?[]const u8) BufferMetadata {
        const now = std.time.milliTimestamp();
        return .{
            .id = id,
            .filepath = if (filepath) |path| path else null,
            .modified = false,
            .readonly = false,
            .created_at = now,
            .modified_at = now,
        };
    }

    pub fn markModified(self: *BufferMetadata) void {
        self.modified = true;
        self.modified_at = std.time.milliTimestamp();
    }

    pub fn markSaved(self: *BufferMetadata) void {
        self.modified = false;
        self.modified_at = std.time.milliTimestamp();
    }

    pub fn getName(self: *const BufferMetadata) []const u8 {
        if (self.filepath) |path| {
            // Extract filename from path
            var i = path.len;
            while (i > 0) {
                i -= 1;
                if (path[i] == '/' or path[i] == '\\') {
                    return path[i + 1 ..];
                }
            }
            return path;
        }
        return "[No Name]";
    }
};

/// A text buffer with content and metadata
pub const Buffer = struct {
    metadata: BufferMetadata,
    rope: Rope,
    allocator: std.mem.Allocator,

    /// Create empty buffer
    pub fn initEmpty(allocator: std.mem.Allocator, id: BufferId) Buffer {
        return .{
            .metadata = BufferMetadata.init(id, null),
            .rope = Rope.init(allocator),
            .allocator = allocator,
        };
    }

    /// Create buffer from file
    pub fn initFromFile(allocator: std.mem.Allocator, id: BufferId, filepath: []const u8) !Buffer {
        // Read file content
        const file = try std.fs.cwd().openFile(filepath, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
        defer allocator.free(content);

        // Create rope from content
        const rope = try Rope.initFromString(allocator, content);

        // Duplicate filepath for metadata
        const owned_path = try allocator.dupe(u8, filepath);

        return .{
            .metadata = BufferMetadata.init(id, owned_path),
            .rope = rope,
            .allocator = allocator,
        };
    }

    /// Create buffer from string
    pub fn initFromString(allocator: std.mem.Allocator, id: BufferId, content: []const u8) !Buffer {
        const rope = try Rope.initFromString(allocator, content);

        return .{
            .metadata = BufferMetadata.init(id, null),
            .rope = rope,
            .allocator = allocator,
        };
    }

    /// Clean up buffer
    pub fn deinit(self: *Buffer) void {
        self.rope.deinit();
        if (self.metadata.filepath) |path| {
            self.allocator.free(path);
        }
    }

    /// Insert text at byte position
    pub fn insert(self: *Buffer, pos: usize, text: []const u8) !void {
        try self.rope.insert(pos, text);
        self.metadata.markModified();
    }

    /// Delete text in byte range
    pub fn delete(self: *Buffer, start: usize, end: usize) !void {
        try self.rope.delete(start, end);
        self.metadata.markModified();
    }

    /// Get line count
    pub fn lineCount(self: *const Buffer) usize {
        return self.rope.lineCount();
    }

    /// Get byte length
    pub fn len(self: *const Buffer) usize {
        return self.rope.len();
    }

    /// Get text content as string (allocates)
    pub fn getText(self: *const Buffer) ![]u8 {
        return self.rope.toString(self.allocator);
    }

    /// Save buffer to file
    pub fn save(self: *Buffer) !void {
        const filepath = self.metadata.filepath orelse return error.NoFilepath;

        // Get buffer content
        const content = try self.getText();
        defer self.allocator.free(content);

        // Write to file
        const file = try std.fs.cwd().createFile(filepath, .{});
        defer file.close();

        try file.writeAll(content);

        self.metadata.markSaved();
    }

    /// Save buffer to new file
    pub fn saveAs(self: *Buffer, filepath: []const u8) !void {
        // Free old filepath if exists
        if (self.metadata.filepath) |old_path| {
            self.allocator.free(old_path);
        }

        // Duplicate new filepath
        self.metadata.filepath = try self.allocator.dupe(u8, filepath);

        // Save to file
        try self.save();
    }
};

/// Buffer manager - manages multiple buffers
pub const BufferManager = struct {
    buffers: std.ArrayList(Buffer),
    active_buffer_id: ?BufferId,
    next_id: BufferId,
    allocator: std.mem.Allocator,

    /// Initialize buffer manager
    pub fn init(allocator: std.mem.Allocator) BufferManager {
        return .{
            .buffers = std.ArrayList(Buffer).empty,
            .active_buffer_id = null,
            .next_id = 1,
            .allocator = allocator,
        };
    }

    /// Clean up all buffers
    pub fn deinit(self: *BufferManager) void {
        for (self.buffers.items) |*buffer| {
            buffer.deinit();
        }
        self.buffers.deinit(self.allocator);
    }

    /// Create new empty buffer
    pub fn createEmpty(self: *BufferManager) !BufferId {
        const id = self.next_id;
        self.next_id += 1;

        const buffer = Buffer.initEmpty(self.allocator, id);
        try self.buffers.append(self.allocator, buffer);

        self.active_buffer_id = id;
        return id;
    }

    /// Open file into new buffer
    pub fn openFile(self: *BufferManager, filepath: []const u8) !BufferId {
        const id = self.next_id;
        self.next_id += 1;

        const buffer = try Buffer.initFromFile(self.allocator, id, filepath);
        try self.buffers.append(self.allocator, buffer);

        self.active_buffer_id = id;
        return id;
    }

    /// Create buffer from string
    pub fn createFromString(self: *BufferManager, content: []const u8) !BufferId {
        const id = self.next_id;
        self.next_id += 1;

        const buffer = try Buffer.initFromString(self.allocator, id, content);
        try self.buffers.append(self.allocator, buffer);

        self.active_buffer_id = id;
        return id;
    }

    /// Get buffer by ID
    pub fn getBuffer(self: *const BufferManager, id: BufferId) ?*const Buffer {
        for (self.buffers.items) |*buffer| {
            if (buffer.metadata.id == id) {
                return buffer;
            }
        }
        return null;
    }

    /// Get active buffer
    pub fn getActiveBuffer(self: *const BufferManager) ?*const Buffer {
        if (self.active_buffer_id) |id| {
            return self.getBuffer(id);
        }
        return null;
    }

    /// Switch to buffer by ID
    pub fn switchTo(self: *BufferManager, id: BufferId) !void {
        if (self.getBuffer(id)) |_| {
            self.active_buffer_id = id;
        } else {
            return error.BufferNotFound;
        }
    }

    /// Close buffer by ID
    pub fn closeBuffer(self: *BufferManager, id: BufferId) !void {
        const items = self.buffers.items(self.allocator);
        for (items, 0..) |*buffer, i| {
            if (buffer.metadata.id == id) {
                buffer.deinit();

                // Remove from list
                var new_buffers: std.ArrayList(Buffer) = .empty;
                for (items, 0..) |item, j| {
                    if (i != j) {
                        try new_buffers.append(self.allocator, item);
                    }
                }

                self.buffers.deinit(self.allocator);
                self.buffers = new_buffers;

                // Update active buffer if needed
                if (self.active_buffer_id == id) {
                    const remaining = self.buffers.items(self.allocator);
                    self.active_buffer_id = if (remaining.len > 0) remaining[0].metadata.id else null;
                }

                return;
            }
        }
        return error.BufferNotFound;
    }

    /// Get buffer count
    pub fn count(self: *const BufferManager) usize {
        return self.buffers.len(self.allocator);
    }

    /// Get list of all buffers
    pub fn listBuffers(self: *const BufferManager) []const Buffer {
        return self.buffers.items(self.allocator);
    }

    /// Check if there are unsaved changes
    pub fn hasUnsavedChanges(self: *const BufferManager) bool {
        const items = self.buffers.items(self.allocator);
        for (items) |buffer| {
            if (buffer.metadata.modified) {
                return true;
            }
        }
        return false;
    }
};

test "buffer: init empty" {
    const allocator = std.testing.allocator;
    var buffer = Buffer.initEmpty(allocator, 1);
    defer buffer.deinit();

    try std.testing.expectEqual(@as(usize, 0), buffer.len());
    try std.testing.expectEqual(@as(usize, 1), buffer.lineCount());
}

test "buffer: init from string" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromString(allocator, 1, "Hello\nWorld");
    defer buffer.deinit();

    try std.testing.expectEqual(@as(usize, 11), buffer.len());
    try std.testing.expectEqual(@as(usize, 2), buffer.lineCount());
}

test "buffer: insert and delete" {
    const allocator = std.testing.allocator;
    var buffer = try Buffer.initFromString(allocator, 1, "Hello");
    defer buffer.deinit();

    try buffer.insert(5, " World");
    try std.testing.expectEqual(@as(usize, 11), buffer.len());

    try buffer.delete(5, 11);
    try std.testing.expectEqual(@as(usize, 5), buffer.len());
}

test "buffer manager: create and switch" {
    const allocator = std.testing.allocator;
    var manager = BufferManager.init(allocator);
    defer manager.deinit();

    const id1 = try manager.createEmpty();
    const id2 = try manager.createFromString("Test");

    try std.testing.expectEqual(@as(usize, 2), manager.count());
    try std.testing.expectEqual(id2, manager.active_buffer_id.?);

    try manager.switchTo(id1);
    try std.testing.expectEqual(id1, manager.active_buffer_id.?);
}

test "buffer manager: close buffer" {
    const allocator = std.testing.allocator;
    var manager = BufferManager.init(allocator);
    defer manager.deinit();

    const id1 = try manager.createEmpty();
    _ = try manager.createEmpty();

    try std.testing.expectEqual(@as(usize, 2), manager.count());

    try manager.closeBuffer(id1);
    try std.testing.expectEqual(@as(usize, 1), manager.count());
}

test "buffer metadata: name extraction" {
    var meta = BufferMetadata.init(1, "/path/to/file.txt");
    try std.testing.expectEqualStrings("file.txt", meta.getName());

    meta.filepath = null;
    try std.testing.expectEqualStrings("[No Name]", meta.getName());
}
