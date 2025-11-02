//! LSP text document synchronization
//! Manages document lifecycle and change tracking

const std = @import("std");
const Client = @import("client.zig").Client;

/// Text document identifier
pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};

/// Versioned text document identifier
pub const VersionedTextDocumentIdentifier = struct {
    uri: []const u8,
    version: i32,
};

/// Text document item (for didOpen)
pub const TextDocumentItem = struct {
    uri: []const u8,
    language_id: []const u8,
    version: i32,
    text: []const u8,
};

/// Text document content change
pub const TextDocumentContentChangeEvent = struct {
    text: []const u8, // Full document text (incremental changes not yet supported)
};

/// Document synchronization manager
pub const SyncManager = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap(DocumentState),

    pub const DocumentState = struct {
        uri: []const u8,
        language_id: []const u8,
        version: i32,
        synced: bool,
    };

    /// Initialize sync manager
    pub fn init(allocator: std.mem.Allocator) SyncManager {
        return .{
            .allocator = allocator,
            .documents = std.StringHashMap(DocumentState).init(allocator),
        };
    }

    /// Clean up sync manager
    pub fn deinit(self: *SyncManager) void {
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.uri);
            self.allocator.free(entry.value_ptr.language_id);
        }
        self.documents.deinit();
    }

    /// Create didOpen notification
    pub fn didOpen(
        self: *SyncManager,
        uri: []const u8,
        language_id: []const u8,
        text: []const u8,
    ) !DidOpenParams {
        const uri_copy = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(uri_copy);

        const lang_copy = try self.allocator.dupe(u8, language_id);
        errdefer self.allocator.free(lang_copy);

        try self.documents.put(uri, .{
            .uri = uri_copy,
            .language_id = lang_copy,
            .version = 1,
            .synced = true,
        });

        return .{
            .text_document = .{
                .uri = uri,
                .language_id = language_id,
                .version = 1,
                .text = text,
            },
        };
    }

    /// Create didChange notification
    pub fn didChange(
        self: *SyncManager,
        uri: []const u8,
        text: []const u8,
    ) !DidChangeParams {
        const state = self.documents.getPtr(uri) orelse return error.DocumentNotOpen;

        state.version += 1;

        return .{
            .text_document = .{
                .uri = uri,
                .version = state.version,
            },
            .content_changes = &[_]TextDocumentContentChangeEvent{
                .{ .text = text },
            },
        };
    }

    /// Create didSave notification
    pub fn didSave(
        self: *SyncManager,
        uri: []const u8,
        text: ?[]const u8,
    ) !DidSaveParams {
        const state = self.documents.get(uri) orelse return error.DocumentNotOpen;
        _ = state;

        return .{
            .text_document = .{ .uri = uri },
            .text = text,
        };
    }

    /// Create didClose notification
    pub fn didClose(self: *SyncManager, uri: []const u8) !DidCloseParams {
        if (self.documents.fetchRemove(uri)) |entry| {
            self.allocator.free(entry.value.uri);
            self.allocator.free(entry.value.language_id);
        }

        return .{
            .text_document = .{ .uri = uri },
        };
    }

    /// Get document version
    pub fn getVersion(self: *const SyncManager, uri: []const u8) ?i32 {
        const state = self.documents.get(uri) orelse return null;
        return state.version;
    }

    /// Check if document is synced
    pub fn isSynced(self: *const SyncManager, uri: []const u8) bool {
        const state = self.documents.get(uri) orelse return false;
        return state.synced;
    }
};

// === Notification parameters ===

pub const DidOpenParams = struct {
    text_document: TextDocumentItem,
};

pub const DidChangeParams = struct {
    text_document: VersionedTextDocumentIdentifier,
    content_changes: []const TextDocumentContentChangeEvent,
};

pub const DidSaveParams = struct {
    text_document: TextDocumentIdentifier,
    text: ?[]const u8 = null,
};

pub const DidCloseParams = struct {
    text_document: TextDocumentIdentifier,
};

// === Tests ===

test "sync: didOpen" {
    const allocator = std.testing.allocator;
    var sync = SyncManager.init(allocator);
    defer sync.deinit();

    const params = try sync.didOpen("file:///test.zig", "zig", "const x = 42;");

    try std.testing.expectEqualStrings("file:///test.zig", params.text_document.uri);
    try std.testing.expectEqualStrings("zig", params.text_document.language_id);
    try std.testing.expectEqual(@as(i32, 1), params.text_document.version);
    try std.testing.expectEqualStrings("const x = 42;", params.text_document.text);
}

test "sync: didChange increments version" {
    const allocator = std.testing.allocator;
    var sync = SyncManager.init(allocator);
    defer sync.deinit();

    _ = try sync.didOpen("file:///test.zig", "zig", "const x = 42;");

    const params1 = try sync.didChange("file:///test.zig", "const x = 43;");
    try std.testing.expectEqual(@as(i32, 2), params1.text_document.version);

    const params2 = try sync.didChange("file:///test.zig", "const x = 44;");
    try std.testing.expectEqual(@as(i32, 3), params2.text_document.version);
}

test "sync: didClose removes document" {
    const allocator = std.testing.allocator;
    var sync = SyncManager.init(allocator);
    defer sync.deinit();

    _ = try sync.didOpen("file:///test.zig", "zig", "const x = 42;");
    try std.testing.expect(sync.isSynced("file:///test.zig"));

    _ = try sync.didClose("file:///test.zig");
    try std.testing.expect(!sync.isSynced("file:///test.zig"));
}

test "sync: getVersion" {
    const allocator = std.testing.allocator;
    var sync = SyncManager.init(allocator);
    defer sync.deinit();

    _ = try sync.didOpen("file:///test.zig", "zig", "const x = 42;");
    try std.testing.expectEqual(@as(i32, 1), sync.getVersion("file:///test.zig").?);

    _ = try sync.didChange("file:///test.zig", "const x = 43;");
    try std.testing.expectEqual(@as(i32, 2), sync.getVersion("file:///test.zig").?);
}
