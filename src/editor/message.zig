//! Message display system for user feedback
//! Shows info, warnings, errors with auto-dismiss

const std = @import("std");

/// Message severity level
pub const Level = enum {
    info,
    warning,
    error_msg,
    success,

    /// Get display color for level
    pub fn color(self: Level) u8 {
        return switch (self) {
            .info => 4, // Blue
            .warning => 3, // Yellow
            .error_msg => 1, // Red
            .success => 2, // Green
        };
    }

    /// Get display name
    pub fn name(self: Level) []const u8 {
        return switch (self) {
            .info => "INFO",
            .warning => "WARNING",
            .error_msg => "ERROR",
            .success => "SUCCESS",
        };
    }

    /// Get auto-dismiss timeout (milliseconds)
    pub fn timeout(self: Level) i64 {
        return switch (self) {
            .info => 3000,
            .warning => 5000,
            .error_msg => 8000,
            .success => 2000,
        };
    }
};

/// A single message
pub const Message = struct {
    content: []const u8,
    level: Level,
    timestamp: i64,

    pub fn init(content: []const u8, level: Level) Message {
        return .{
            .content = content,
            .level = level,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    /// Check if message should be auto-dismissed
    pub fn shouldDismiss(self: *const Message) bool {
        const now = std.time.milliTimestamp();
        const elapsed = now - self.timestamp;
        return elapsed > self.level.timeout();
    }
};

/// Message queue with capacity limit
pub const MessageQueue = struct {
    messages: [10]Message,
    len: usize,
    allocator: std.mem.Allocator,

    /// Initialize empty queue
    pub fn init(allocator: std.mem.Allocator) MessageQueue {
        return .{
            .messages = undefined,
            .len = 0,
            .allocator = allocator,
        };
    }

    /// Add a message (pushes out oldest if full)
    pub fn add(self: *MessageQueue, content: []const u8, level: Level) !void {
        // Make owned copy of content
        const owned_content = try self.allocator.dupe(u8, content);
        const msg = Message.init(owned_content, level);

        // If full, remove oldest and free its content
        if (self.len == self.messages.len) {
            const oldest = self.messages[0];
            self.allocator.free(oldest.content);

            // Shift messages down
            var i: usize = 0;
            while (i < self.len - 1) : (i += 1) {
                self.messages[i] = self.messages[i + 1];
            }
            self.len -= 1;
        }

        // Add new message at end
        self.messages[self.len] = msg;
        self.len += 1;
    }

    /// Get current message (most recent that hasn't timed out)
    pub fn current(self: *MessageQueue) ?Message {
        // Clean up old messages
        self.cleanup();

        // Return most recent if any
        if (self.len > 0) {
            return self.messages[self.len - 1];
        }
        return null;
    }

    /// Get all messages
    pub fn all(self: *const MessageQueue) []const Message {
        return self.messages[0..self.len];
    }

    /// Remove messages that have timed out
    fn cleanup(self: *MessageQueue) void {
        var i: usize = 0;
        while (i < self.len) {
            if (self.messages[i].shouldDismiss()) {
                const msg = self.messages[i];
                self.allocator.free(msg.content);

                // Shift remaining messages down
                var j = i;
                while (j < self.len - 1) : (j += 1) {
                    self.messages[j] = self.messages[j + 1];
                }
                self.len -= 1;
                // Don't increment i - we removed an element
            } else {
                i += 1;
            }
        }
    }

    /// Clear all messages
    pub fn clear(self: *MessageQueue) void {
        for (self.messages[0..self.len]) |msg| {
            self.allocator.free(msg.content);
        }
        self.len = 0;
    }

    /// Clean up
    pub fn deinit(self: *MessageQueue) void {
        self.clear();
    }
};

// === Tests ===

test "message: timeout" {
    const msg = Message.init("test", .info);
    try std.testing.expect(!msg.shouldDismiss()); // Immediately shouldn't dismiss
}

test "message queue: add and retrieve" {
    const allocator = std.testing.allocator;
    var queue = MessageQueue.init(allocator);
    defer queue.deinit();

    try queue.add("Test message", .info);

    const curr = queue.current();
    try std.testing.expect(curr != null);
    try std.testing.expectEqualStrings("Test message", curr.?.content);
}

test "message queue: overflow" {
    const allocator = std.testing.allocator;
    var queue = MessageQueue.init(allocator);
    defer queue.deinit();

    // Add more than capacity
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        var buf: [32]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "Message {d}", .{i});
        try queue.add(msg, .info);
    }

    // Should only have last 10
    try std.testing.expectEqual(@as(usize, 10), queue.len);
}
