//! Diagnostic management for LSP
//! Stores and retrieves diagnostics per file

const std = @import("std");
const ResponseParser = @import("response_parser.zig");

pub const Diagnostic = ResponseParser.Diagnostic;
pub const DiagnosticSeverity = ResponseParser.DiagnosticSeverity;

/// Diagnostic manager - stores diagnostics per URI
pub const DiagnosticManager = struct {
    allocator: std.mem.Allocator,
    /// Map from file URI to diagnostics
    diagnostics_by_uri: std.StringHashMap([]Diagnostic),

    pub fn init(allocator: std.mem.Allocator) DiagnosticManager {
        return .{
            .allocator = allocator,
            .diagnostics_by_uri = std.StringHashMap([]Diagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *DiagnosticManager) void {
        // Free all diagnostics
        var iter = self.diagnostics_by_uri.iterator();
        while (iter.next()) |entry| {
            // Free the key (URI)
            self.allocator.free(entry.key_ptr.*);
            // Free each diagnostic in the array
            for (entry.value_ptr.*) |*diag| {
                diag.deinit(self.allocator);
            }
            // Free the array itself
            self.allocator.free(entry.value_ptr.*);
        }
        self.diagnostics_by_uri.deinit();
    }

    /// Update diagnostics for a given URI (takes ownership of uri and diagnostics)
    pub fn update(self: *DiagnosticManager, uri: []const u8, diagnostics: []Diagnostic) !void {
        // Check if we already have diagnostics for this URI
        if (self.diagnostics_by_uri.get(uri)) |old_diagnostics| {
            // Free old diagnostics
            for (old_diagnostics) |*diag| {
                diag.deinit(self.allocator);
            }
            self.allocator.free(old_diagnostics);

            // Update with new diagnostics (reuse existing key)
            try self.diagnostics_by_uri.put(uri, diagnostics);
            // Free the new URI since we're reusing the old key
            self.allocator.free(uri);
        } else {
            // New URI, insert directly
            try self.diagnostics_by_uri.put(uri, diagnostics);
        }
    }

    /// Get diagnostics for a given URI (returns borrowed slice)
    pub fn get(self: *const DiagnosticManager, uri: []const u8) ?[]const Diagnostic {
        return self.diagnostics_by_uri.get(uri);
    }

    /// Get diagnostics for a specific line in a file
    /// Note: Returns empty slice - use getSeverestForLine for practical usage
    pub fn getForLine(self: *const DiagnosticManager, uri: []const u8, line: u32) []const Diagnostic {
        _ = self;
        _ = uri;
        _ = line;
        // This would require allocating a new array, which needs an allocator parameter
        // For now, use getSeverestForLine() which returns the most severe diagnostic
        return &[_]Diagnostic{};
    }

    /// Get most severe diagnostic for a line
    pub fn getSeverestForLine(self: *const DiagnosticManager, uri: []const u8, line: u32) ?Diagnostic {
        const all_diagnostics = self.get(uri) orelse return null;

        var severest: ?Diagnostic = null;
        var severest_level: u8 = 255;

        for (all_diagnostics) |diag| {
            if (diag.range.start.line == line) {
                const level = @intFromEnum(diag.severity);
                if (level < severest_level) {
                    severest = diag;
                    severest_level = level;
                }
            }
        }

        return severest;
    }

    /// Clear diagnostics for a URI
    pub fn clear(self: *DiagnosticManager, uri: []const u8) void {
        if (self.diagnostics_by_uri.fetchRemove(uri)) |entry| {
            self.allocator.free(entry.key);
            for (entry.value) |*diag| {
                diag.deinit(self.allocator);
            }
            self.allocator.free(entry.value);
        }
    }

    /// Clear all diagnostics
    pub fn clearAll(self: *DiagnosticManager) void {
        var iter = self.diagnostics_by_uri.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |*diag| {
                diag.deinit(self.allocator);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.diagnostics_by_uri.clearRetainingCapacity();
    }

    /// Get total diagnostic count across all files
    pub fn getTotalCount(self: *const DiagnosticManager) usize {
        var total: usize = 0;
        var iter = self.diagnostics_by_uri.valueIterator();
        while (iter.next()) |diagnostics| {
            total += diagnostics.len;
        }
        return total;
    }

    /// Get diagnostic counts by severity
    pub fn getCountsBySeverity(self: *const DiagnosticManager) struct {
        errors: usize,
        warnings: usize,
        info: usize,
        hints: usize,
    } {
        var errors: usize = 0;
        var warnings: usize = 0;
        var info: usize = 0;
        var hints: usize = 0;

        var iter = self.diagnostics_by_uri.valueIterator();
        while (iter.next()) |diagnostics| {
            for (diagnostics.*) |diag| {
                switch (diag.severity) {
                    .@"error" => errors += 1,
                    .warning => warnings += 1,
                    .information => info += 1,
                    .hint => hints += 1,
                }
            }
        }

        return .{
            .errors = errors,
            .warnings = warnings,
            .info = info,
            .hints = hints,
        };
    }
};

// === Tests ===

test "diagnostics: init and deinit" {
    const allocator = std.testing.allocator;
    var manager = DiagnosticManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(usize, 0), manager.getTotalCount());
}

test "diagnostics: update and get" {
    const allocator = std.testing.allocator;
    var manager = DiagnosticManager.init(allocator);
    defer manager.deinit();

    const uri = try allocator.dupe(u8, "file:///test.zig");
    var diagnostics = try allocator.alloc(Diagnostic, 1);
    diagnostics[0] = Diagnostic{
        .range = .{
            .start = .{ .line = 5, .character = 0 },
            .end = .{ .line = 5, .character = 10 },
        },
        .severity = .@"error",
        .code = null,
        .source = null,
        .message = try allocator.dupe(u8, "test error"),
    };

    try manager.update(uri, diagnostics);

    const retrieved = manager.get("file:///test.zig");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(usize, 1), retrieved.?.len);
    try std.testing.expectEqual(DiagnosticSeverity.@"error", retrieved.?[0].severity);
}

test "diagnostics: get counts by severity" {
    const allocator = std.testing.allocator;
    var manager = DiagnosticManager.init(allocator);
    defer manager.deinit();

    const uri = try allocator.dupe(u8, "file:///test.zig");
    var diagnostics = try allocator.alloc(Diagnostic, 3);

    diagnostics[0] = Diagnostic{
        .range = .{
            .start = .{ .line = 1, .character = 0 },
            .end = .{ .line = 1, .character = 10 },
        },
        .severity = .@"error",
        .code = null,
        .source = null,
        .message = try allocator.dupe(u8, "error"),
    };

    diagnostics[1] = Diagnostic{
        .range = .{
            .start = .{ .line = 2, .character = 0 },
            .end = .{ .line = 2, .character = 10 },
        },
        .severity = .warning,
        .code = null,
        .source = null,
        .message = try allocator.dupe(u8, "warning"),
    };

    diagnostics[2] = Diagnostic{
        .range = .{
            .start = .{ .line = 3, .character = 0 },
            .end = .{ .line = 3, .character = 10 },
        },
        .severity = .@"error",
        .code = null,
        .source = null,
        .message = try allocator.dupe(u8, "another error"),
    };

    try manager.update(uri, diagnostics);

    const counts = manager.getCountsBySeverity();
    try std.testing.expectEqual(@as(usize, 2), counts.errors);
    try std.testing.expectEqual(@as(usize, 1), counts.warnings);
    try std.testing.expectEqual(@as(usize, 0), counts.info);
    try std.testing.expectEqual(@as(usize, 0), counts.hints);
}

test "diagnostics: get severest for line" {
    const allocator = std.testing.allocator;
    var manager = DiagnosticManager.init(allocator);
    defer manager.deinit();

    const uri = try allocator.dupe(u8, "file:///test.zig");
    var diagnostics = try allocator.alloc(Diagnostic, 2);

    diagnostics[0] = Diagnostic{
        .range = .{
            .start = .{ .line = 5, .character = 0 },
            .end = .{ .line = 5, .character = 10 },
        },
        .severity = .warning,
        .code = null,
        .source = null,
        .message = try allocator.dupe(u8, "warning"),
    };

    diagnostics[1] = Diagnostic{
        .range = .{
            .start = .{ .line = 5, .character = 10 },
            .end = .{ .line = 5, .character = 20 },
        },
        .severity = .@"error",
        .code = null,
        .source = null,
        .message = try allocator.dupe(u8, "error"),
    };

    try manager.update(uri, diagnostics);

    const severest = manager.getSeverestForLine("file:///test.zig", 5);
    try std.testing.expect(severest != null);
    try std.testing.expectEqual(DiagnosticSeverity.@"error", severest.?.severity);
}
