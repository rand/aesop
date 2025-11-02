//! Main editor state coordinator
//! Ties together buffers, selections, modes, commands, and rendering

const std = @import("std");
const Mode = @import("mode.zig");
const Cursor = @import("cursor.zig");
const Buffer = @import("../buffer/manager.zig");
const Command = @import("command.zig");
const Keymap = @import("keymap.zig");
const Motions = @import("motions.zig");
const Actions = @import("actions.zig");
const Message = @import("message.zig");
const Undo = @import("undo.zig");
const Palette = @import("palette.zig");
const Search = @import("search.zig");
const Marks = @import("marks.zig");
const Repeat = @import("repeat.zig");
const Prompt = @import("prompt.zig");
const Registers = @import("registers.zig");
const Macros = @import("macros.zig");
const Config = @import("config.zig");
const Window = @import("window.zig");
const FileFinder = @import("file_finder.zig");
const AutoPair = @import("autopair.zig");
const PluginSystem = @import("../plugin/system.zig");
const Renderer = @import("../render/renderer.zig").Renderer;
const LspClient = @import("../lsp/client.zig").Client;
const LspHandlers = @import("../lsp/handlers.zig");
const LspDiagnostics = @import("../lsp/diagnostics.zig");
const CompletionList = @import("completion.zig").CompletionList;

/// Pending command awaiting user input
///
/// Uses continuation-passing style for command resumption. When a command
/// requires user input (e.g., character for find motion, register for marks),
/// it sets this state and activates the prompt. The event loop routes subsequent
/// input to the appropriate completion handler.
///
/// Design rationale: This unified state machine is cleaner than separate boolean
/// flags for each command type, provides type-safe continuation, and encodes
/// command parameters directly in the enum payload.
pub const PendingCommand = union(enum) {
    none,
    /// Find or till character motion (f/F/t/T commands)
    find_char: struct { forward: bool, till: bool },
    /// Set mark at current position (m command)
    set_mark,
    /// Jump to mark (` or ' command)
    goto_mark,
    /// Start macro recording (q command)
    record_macro,
    /// Play macro from register (@ command)
    play_macro,
    /// Replace character at cursor (r command)
    replace_char,

    /// Check if a command is awaiting input
    pub fn isWaiting(self: PendingCommand) bool {
        return self != .none;
    }
};

/// Editor state - the main coordinator
pub const Editor = struct {
    allocator: std.mem.Allocator,

    // Core state
    mode_manager: Mode.ModeManager,
    buffer_manager: Buffer.BufferManager,
    selections: Cursor.SelectionSet,
    command_registry: Command.Registry,
    keymap_manager: Keymap.KeymapManager,
    clipboard: Actions.Clipboard,
    messages: Message.MessageQueue,
    undo_history: Undo.UndoHistory,
    palette: Palette.Palette,
    search: Search.Search,
    marks: Marks.MarkRegistry,
    repeat_system: Repeat.RepeatSystem,
    prompt: Prompt.Prompt,
    registers: Registers.RegisterManager,
    find_till_state: Motions.FindTillState,
    macro_recorder: Macros.MacroRecorder,
    pending_command: PendingCommand,
    config: Config.Config,
    window_manager: Window.WindowManager,
    plugin_manager: PluginSystem.PluginManager,
    file_finder: FileFinder.FileFinder,
    buffer_switcher_visible: bool,
    buffer_switcher_selected: usize,
    lsp_client: ?LspClient, // Optional LSP client (null if not initialized)
    completion_list: CompletionList, // Code completion popup
    diagnostic_manager: LspDiagnostics.DiagnosticManager, // LSP diagnostics storage
    hover_content: ?[]const u8, // Current hover text (allocated, must free)

    // Viewport (legacy - will be replaced by window_manager)
    scroll_offset: usize, // Line offset for scrolling

    /// Initialize editor
    pub fn init(allocator: std.mem.Allocator) !Editor {
        // Initialize window manager with default terminal dimensions
        const initial_dims = Window.Dimensions{
            .row = 0,
            .col = 0,
            .height = 24,
            .width = 80,
        };

        // Initialize config first so we can use it during other initialization
        const config = Config.Config.init(allocator);
        const search_options = Search.SearchOptions{
            .case_sensitive = config.search_case_sensitive,
            .whole_word = false,
            .wrap_around = config.search_wrap_around,
        };

        var editor = Editor{
            .allocator = allocator,
            .mode_manager = Mode.ModeManager.init(),
            .buffer_manager = Buffer.BufferManager.init(allocator),
            .selections = try Cursor.SelectionSet.initWithCursor(allocator, .{ .line = 0, .col = 0 }),
            .command_registry = Command.Registry.init(allocator),
            .keymap_manager = Keymap.KeymapManager.init(allocator),
            .clipboard = Actions.Clipboard.init(allocator),
            .messages = Message.MessageQueue.init(allocator),
            .undo_history = Undo.UndoHistory.init(allocator),
            .palette = Palette.Palette.init(allocator),
            .search = Search.Search.initWithOptions(allocator, search_options),
            .marks = Marks.MarkRegistry.init(allocator),
            .repeat_system = Repeat.RepeatSystem.init(allocator),
            .prompt = Prompt.Prompt.init(allocator),
            .registers = Registers.RegisterManager.init(allocator),
            .find_till_state = Motions.FindTillState{},
            .macro_recorder = Macros.MacroRecorder.init(allocator),
            .pending_command = .none,
            .config = config,
            .window_manager = try Window.WindowManager.init(allocator, initial_dims),
            .plugin_manager = PluginSystem.PluginManager.init(allocator),
            .file_finder = FileFinder.FileFinder.init(allocator),
            .buffer_switcher_visible = false,
            .buffer_switcher_selected = 0,
            .lsp_client = null, // LSP client initialized on-demand
            .completion_list = CompletionList.init(allocator),
            .diagnostic_manager = LspDiagnostics.DiagnosticManager.init(allocator),
            .hover_content = null,
            .scroll_offset = 0,
        };

        // Register built-in commands
        try Command.registerBuiltins(&editor.command_registry);

        // Setup default keymaps
        try Keymap.setupDefaults(&editor.keymap_manager);

        return editor;
    }

    /// Clean up editor
    pub fn deinit(self: *Editor) void {
        if (self.hover_content) |content| {
            self.allocator.free(content);
        }
        self.diagnostic_manager.deinit();
        self.completion_list.deinit();
        if (self.lsp_client) |*client| {
            client.deinit();
        }
        self.file_finder.deinit();
        self.plugin_manager.deinit();
        self.window_manager.deinit();
        self.config.deinit();
        self.macro_recorder.deinit();
        self.registers.deinit();
        self.prompt.deinit();
        self.repeat_system.deinit();
        self.marks.deinit();
        self.search.deinit();
        self.palette.deinit();
        self.undo_history.deinit();
        self.messages.deinit();
        self.clipboard.deinit();
        self.selections.deinit(self.allocator);
        self.buffer_manager.deinit();
        self.command_registry.deinit();
        self.keymap_manager.deinit();
    }

    /// Get current mode
    pub fn getMode(self: *const Editor) Mode.Mode {
        return self.mode_manager.getMode();
    }

    /// Get active buffer
    pub fn getActiveBuffer(self: *const Editor) ?*const Buffer.Buffer {
        return self.buffer_manager.getActiveBuffer();
    }

    /// Create new empty buffer
    pub fn newBuffer(self: *Editor) !void {
        _ = try self.buffer_manager.createEmpty();
        // Reset selections for new buffer
        try self.selections.setSingleCursor(self.allocator, .{ .line = 0, .col = 0 });
        self.scroll_offset = 0;
    }

    /// Open file
    pub fn openFile(self: *Editor, filepath: []const u8) !void {
        const buffer_id = try self.buffer_manager.openFile(filepath);
        // Reset selections for new buffer
        try self.selections.setSingleCursor(self.allocator, .{ .line = 0, .col = 0 });
        self.scroll_offset = 0;

        // Dispatch buffer open event to plugins
        self.plugin_manager.dispatchBufferOpen(buffer_id) catch {};

        // Notify LSP if available
        if (self.lsp_client) |*client| {
            // Set notification handler if not already set
            if (client.notification_handler == null) {
                client.setNotificationHandler(handleLspNotification, self);
            }

            if (client.isReady()) {
                const buffer = self.buffer_manager.getActiveBuffer() orelse return;
                const uri = try self.makeFileUri(filepath);
                defer self.allocator.free(uri);
                const text = try buffer.getText();
                defer self.allocator.free(text);
                LspHandlers.didOpen(client, uri, "zig", 0, text) catch {};
            }
        }
    }

    /// Save active buffer
    pub fn save(self: *Editor) !void {
        if (self.buffer_manager.active_buffer_id) |id| {
            const buffer = self.buffer_manager.getBufferMut(id) orelse return error.NoActiveBuffer;
            const filepath = buffer.metadata.filepath orelse return error.NoFilepath;
            try buffer.save();

            // Dispatch buffer save event to plugins
            self.plugin_manager.dispatchBufferSave(id) catch {};

            // Notify LSP if available
            if (self.lsp_client) |*client| {
                if (client.isReady()) {
                    const uri = try self.makeFileUri(filepath);
                    defer self.allocator.free(uri);
                    LspHandlers.didSave(client, uri, null) catch {};
                }
            }
        } else {
            return error.NoActiveBuffer;
        }
    }

    /// Save active buffer as...
    pub fn saveAs(self: *Editor, filepath: []const u8) !void {
        if (self.buffer_manager.active_buffer_id) |id| {
            const buffer = self.buffer_manager.getBufferMut(id) orelse return error.NoActiveBuffer;
            try buffer.saveAs(filepath);
        } else {
            return error.NoActiveBuffer;
        }
    }

    /// Close active buffer
    pub fn closeBuffer(self: *Editor) !void {
        if (self.buffer_manager.active_buffer_id) |id| {
            const buffer = self.buffer_manager.getBuffer(id) orelse return error.NoActiveBuffer;
            const filepath = buffer.metadata.filepath;

            // Notify LSP before closing
            if (filepath) |path| {
                if (self.lsp_client) |*client| {
                    if (client.isReady()) {
                        const uri = try self.makeFileUri(path);
                        defer self.allocator.free(uri);
                        LspHandlers.didClose(client, uri) catch {};
                    }
                }
            }

            // Dispatch close event to plugins
            self.plugin_manager.dispatchBufferClose(id) catch {};

            // Close buffer in manager
            try self.buffer_manager.closeBuffer(id);
        } else {
            return error.NoActiveBuffer;
        }
    }

    /// Handle LSP notifications from server
    pub fn handleLspNotification(ctx: ?*anyopaque, method: []const u8, params_json: []const u8) !void {
        const self: *Editor = @ptrCast(@alignCast(ctx orelse return));
        const ResponseParser = @import("../lsp/response_parser.zig");

        // Handle textDocument/publishDiagnostics
        if (std.mem.eql(u8, method, "textDocument/publishDiagnostics")) {
            // Parse the params JSON to extract diagnostics
            const result = ResponseParser.parseDiagnosticsNotification(
                self.allocator,
                params_json,
            ) catch |err| {
                std.debug.print("[LSP] Failed to parse diagnostics: {}\n", .{err});
                return;
            };

            // Update diagnostic manager
            self.diagnostic_manager.update(result.uri, result.diagnostics) catch |err| {
                std.debug.print("[LSP] Failed to update diagnostics: {}\n", .{err});
                // Clean up on error
                self.allocator.free(result.uri);
                for (result.diagnostics) |*diag| {
                    diag.deinit(self.allocator);
                }
                self.allocator.free(result.diagnostics);
                return;
            };

            std.debug.print("[LSP] Updated diagnostics for {s}: {} items\n", .{
                result.uri,
                result.diagnostics.len,
            });
        } else {
            // Unknown notification, ignore
            std.debug.print("[LSP] Ignoring notification: {s}\n", .{method});
        }
    }

    /// Create file:// URI from filepath
    pub fn makeFileUri(self: *Editor, filepath: []const u8) ![]u8 {
        // Get absolute path if relative
        const abs_path = if (std.fs.path.isAbsolute(filepath))
            try self.allocator.dupe(u8, filepath)
        else
            try std.fs.cwd().realpathAlloc(self.allocator, filepath);
        defer if (!std.fs.path.isAbsolute(filepath)) self.allocator.free(abs_path);

        // Create file:// URI
        const uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{abs_path});
        return uri;
    }

    /// Process key input
    pub fn processKey(self: *Editor, key: Keymap.Key) !void {
        const mode = self.getMode();

        // Priority 1: Incremental search mode
        if (self.search.incremental) {
            try self.handleSearchInput(key);
            return;
        }

        // Priority 2: Pending command awaiting input
        if (self.pending_command.isWaiting()) {
            try self.handlePendingCommandInput(key);
            return;
        }

        // Priority 3: Try to match key to command
        if (try self.keymap_manager.processKey(mode, key)) |command_name| {
            // Execute command with editor context
            var ctx = Command.Context{ .editor = self };
            const result = self.command_registry.execute(command_name, &ctx);

            switch (result) {
                .success => {},
                .error_msg => |msg| {
                    // Show error in message queue
                    self.messages.add(msg, .error_msg) catch {};
                },
            }

            // Auto-scroll viewport to follow cursor
            self.ensureCursorVisible();
        } else if (mode.acceptsTextInput()) {
            // Handle text input in insert/command mode
            try self.handleTextInput(key);

            // Auto-scroll viewport to follow cursor
            self.ensureCursorVisible();
        }
    }

    /// Handle input during incremental search
    fn handleSearchInput(self: *Editor, key: Keymap.Key) !void {
        switch (key) {
            .char => |c| {
                // Add character to search query
                const char_byte = @as(u8, @intCast(c));
                try self.search.appendChar(char_byte);

                // Update message with current query
                const query = self.search.getQuery();
                const msg = try std.fmt.allocPrint(self.allocator, "Search: {s}", .{query});
                defer self.allocator.free(msg);
                self.messages.add(msg, .info) catch {};

                // Find first match and jump to it
                if (self.buffer_manager.active_buffer_id) |id| {
                    const buffer = self.buffer_manager.getBuffer(id) orelse return;
                    const text = try buffer.getText();
                    defer self.allocator.free(text);

                    const cursor_pos = self.getCursorPosition();
                    if (self.search.findNext(text, cursor_pos)) |match| {
                        try self.selections.setSingleCursor(self.allocator, match.start);
                        self.ensureCursorVisible();
                    }
                }
            },
            .special => |special| {
                switch (special) {
                    .backspace => {
                        self.search.backspace();
                        const query = self.search.getQuery();
                        const msg = try std.fmt.allocPrint(self.allocator, "Search: {s}", .{query});
                        defer self.allocator.free(msg);
                        self.messages.add(msg, .info) catch {};
                    },
                    .enter => {
                        // Accept search and exit incremental mode
                        self.search.incremental = false;
                        self.messages.clear();
                    },
                    .escape => {
                        // Cancel search
                        self.search.clear();
                        self.messages.clear();
                    },
                    else => {},
                }
            },
        }
    }

    /// Handle input when a command is awaiting user response
    ///
    /// Called after a command requests user input via the prompt system.
    /// Input is routed based on pending_command type to the appropriate
    /// completion handler.
    ///
    /// Supports:
    /// - Character input for find/till motions, marks, macros, replace
    /// - Escape key cancels pending command
    ///
    /// After completion or cancellation, pending state is cleared and prompt hidden.
    fn handlePendingCommandInput(self: *Editor, key: Keymap.Key) !void {
        // Handle escape - cancel pending command
        if (key == .special and key.special == .escape) {
            self.pending_command = .none;
            self.prompt.hide();
            self.messages.clear();
            return;
        }

        // Extract character from key input
        const char_byte = switch (key) {
            .char => |c| @as(u8, @intCast(c)),
            .special => return, // Ignore other special keys
        };

        // Dispatch to appropriate completion handler based on pending command type
        switch (self.pending_command) {
            .none => unreachable, // Should not be called if no pending command

            .find_char => |params| {
                self.pending_command = .none;
                self.prompt.hide();
                try self.completeFindChar(char_byte, params.forward, params.till);
            },

            .set_mark => {
                self.pending_command = .none;
                self.prompt.hide();
                try self.completeSetMark(char_byte);
            },

            .goto_mark => {
                self.pending_command = .none;
                self.prompt.hide();
                try self.completeGotoMark(char_byte);
            },

            .record_macro => {
                self.pending_command = .none;
                self.prompt.hide();
                try self.completeRecordMacro(char_byte);
            },

            .play_macro => {
                self.pending_command = .none;
                self.prompt.hide();
                try self.completePlayMacro(char_byte);
            },

            .replace_char => {
                self.pending_command = .none;
                self.prompt.hide();
                try self.completeReplaceChar(char_byte);
            },
        }

        self.ensureCursorVisible();
    }

    /// Ensure cursor is visible in viewport (auto-scroll)
    pub fn ensureCursorVisible(self: *Editor) void {
        const cursor_pos = self.getCursorPosition();
        const buffer = self.getActiveBuffer() orelse return;
        const total_lines = buffer.lineCount();

        // Assume standard terminal height for now (will be passed from renderer later)
        const viewport_height: usize = 24;
        const visible_lines = viewport_height -| 2; // Reserve for status

        // Calculate desired viewport bounds
        const viewport_end = self.scroll_offset + visible_lines;

        // Scroll down if cursor is below viewport
        if (cursor_pos.line >= viewport_end) {
            self.scroll_offset = cursor_pos.line -| (visible_lines - 1);
        }

        // Scroll up if cursor is above viewport
        if (cursor_pos.line < self.scroll_offset) {
            self.scroll_offset = cursor_pos.line;
        }

        // Clamp to valid range
        const max_scroll = if (total_lines > visible_lines) total_lines - visible_lines else 0;
        self.scroll_offset = @min(self.scroll_offset, max_scroll);
    }

    /// Handle text input (characters, newlines, backspace, tab)
    fn handleTextInput(self: *Editor, key: Keymap.Key) !void {
        // Get mutable buffer reference for text modification
        if (self.buffer_manager.active_buffer_id) |id| {
            const buffer = self.buffer_manager.getBufferMut(id) orelse return error.NoActiveBuffer;

            // Get all selections
            const all_selections = self.selections.all(self.allocator);

            // Check for auto-pairing
            const autopair_config = AutoPair.AutoPairConfig{ .enabled = self.config.auto_pair_brackets };
            const should_pair = if (key == .char)
                AutoPair.shouldAutoPair(autopair_config, key.char)
            else
                false;

            // Determine text to insert
            const text_to_insert: ?[]const u8 = switch (key) {
                .char => |codepoint| blk: {
                    // Check for auto-pairing
                    if (should_pair) {
                        break :blk try AutoPair.getPairedText(autopair_config, codepoint, self.allocator);
                    }

                    // Convert character to UTF-8 bytes
                    var buf: [4]u8 = undefined;
                    const len = try std.unicode.utf8Encode(codepoint, &buf);
                    // Allocate persistent storage for the character
                    const persistent = try self.allocator.alloc(u8, len);
                    @memcpy(persistent, buf[0..len]);
                    break :blk persistent;
                },
                .special => |special_key| switch (special_key) {
                    .enter => "\n",
                    .tab => try self.config.getTabString(self.allocator),
                    else => null,
                },
            };
            defer if (text_to_insert) |txt| {
                // Free if we allocated
                if (key == .char or (key == .special and key.special == .tab)) {
                    self.allocator.free(txt);
                }
            };

            // Apply operation to all cursors (in reverse order to maintain positions)
            var new_selections = std.ArrayList(Cursor.Selection).empty;
            defer new_selections.deinit(self.allocator);

            var i: usize = all_selections.len;
            while (i > 0) {
                i -= 1;
                const sel = all_selections[i];

                var new_sel = blk: {
                    if (text_to_insert) |txt| {
                        break :blk try Actions.insertText(buffer, sel, txt);
                    } else if (key == .special) {
                        // Handle backspace specially
                        if (key.special == .backspace) {
                            break :blk try Actions.deleteCharBefore(buffer, sel);
                        }
                    }
                    break :blk sel;
                };

                // Adjust cursor position for auto-pairing (move back one char to be between pair)
                if (should_pair and text_to_insert != null) {
                    // Move cursor back one column to position between opening and closing char
                    if (new_sel.head.col > 0) {
                        new_sel.head.col -= 1;
                        new_sel.anchor.col = new_sel.head.col;
                    }
                }

                // Prepend to maintain order
                try new_selections.insert(self.allocator, 0, new_sel);
            }

            // Update all selections
            self.selections.clear(self.allocator);
            for (new_selections.items) |sel| {
                try self.selections.add(self.allocator, sel);
            }
            self.selections.primary_index = if (new_selections.items.len > 0) new_selections.items.len - 1 else 0;

            // Mark buffer as modified
            buffer.metadata.markModified();
        }
    }

    /// Handle mode transitions
    pub fn enterNormalMode(self: *Editor) !void {
        const old_mode = self.mode_manager.getMode();
        try self.mode_manager.enterNormal();
        self.keymap_manager.clearPending();

        // Dispatch mode change to plugins
        self.plugin_manager.dispatchModeChange(@intFromEnum(old_mode), @intFromEnum(Mode.Mode.normal)) catch {};
    }

    pub fn enterInsertMode(self: *Editor) !void {
        const old_mode = self.mode_manager.getMode();
        try self.mode_manager.enterInsert();
        self.keymap_manager.clearPending();

        // Dispatch mode change to plugins
        self.plugin_manager.dispatchModeChange(@intFromEnum(old_mode), @intFromEnum(Mode.Mode.insert)) catch {};
    }

    pub fn enterSelectMode(self: *Editor) !void {
        const old_mode = self.mode_manager.getMode();
        try self.mode_manager.enterSelect();
        self.keymap_manager.clearPending();

        // Dispatch mode change to plugins
        self.plugin_manager.dispatchModeChange(@intFromEnum(old_mode), @intFromEnum(Mode.Mode.select)) catch {};
    }

    /// Get viewport info for rendering
    pub fn getViewport(self: *const Editor, screen_height: usize) struct {
        start_line: usize,
        end_line: usize,
    } {
        const buffer = self.buffer_manager.getActiveBuffer();
        const total_lines = if (buffer) |b| b.lineCount() else 0;

        const visible_lines = screen_height -| 2; // Reserve space for status line
        const end_line = @min(self.scroll_offset + visible_lines, total_lines);

        return .{
            .start_line = self.scroll_offset,
            .end_line = end_line,
        };
    }

    /// Scroll viewport
    pub fn scroll(self: *Editor, delta: isize) void {
        if (delta < 0) {
            const abs_delta: usize = @intCast(@abs(delta));
            self.scroll_offset -|= abs_delta;
        } else {
            self.scroll_offset += @intCast(delta);
        }
    }

    /// Get cursor position (primary selection head)
    pub fn getCursorPosition(self: *const Editor) Cursor.Position {
        if (self.selections.primary(self.allocator)) |sel| {
            return sel.head;
        }
        return .{ .line = 0, .col = 0 };
    }

    /// Get status line info
    pub fn getStatusInfo(self: *const Editor) StatusInfo {
        const buffer = self.buffer_manager.getActiveBuffer();
        const cursor_pos = self.getCursorPosition();

        const total_lines = if (buffer) |b| b.lineCount() else 0;
        const current_line = cursor_pos.line + 1;
        const percent = if (total_lines > 0)
            @min(100, (current_line * 100) / total_lines)
        else
            0;

        return .{
            .mode = self.getMode(),
            .buffer_name = if (buffer) |b| b.metadata.getName() else "[No Name]",
            .file_path = if (buffer) |b| b.metadata.filepath else null,
            .modified = if (buffer) |b| b.metadata.modified else false,
            .readonly = if (buffer) |b| b.metadata.readonly else false,
            .line = current_line, // 1-indexed for display
            .col = cursor_pos.col + 1,
            .total_lines = total_lines,
            .percent = percent,
            .selection_count = self.selections.count(self.allocator),
            .can_undo = self.undo_history.canUndo(),
            .can_redo = self.undo_history.canRedo(),
        };
    }

    // === Pending Command Completion Handlers ===

    /// Complete find/till character motion with user-provided character
    ///
    /// Executes the find or till motion using the provided character.
    /// Parameters (forward, till) were captured during command initiation and
    /// passed through the PendingCommand payload, allowing a single completion
    /// handler to serve all four variants (f/F/t/T).
    ///
    /// Updates find_till_state to enable repeat commands (;/,) without prompting again.
    /// In visual mode, extends selection rather than moving cursor alone.
    fn completeFindChar(self: *Editor, ch: u8, forward: bool, till: bool) !void {
        const buffer = self.getActiveBuffer() orelse return error.NoActiveBuffer;
        const primary_sel = self.selections.primary(self.allocator) orelse return error.NoSelection;

        // Execute the appropriate motion
        const new_sel = if (forward) blk: {
            if (till) {
                break :blk Motions.tillCharForward(primary_sel, buffer, ch);
            } else {
                break :blk Motions.findCharForward(primary_sel, buffer, ch);
            }
        } else blk: {
            if (till) {
                break :blk Motions.tillCharBackward(primary_sel, buffer, ch);
            } else {
                break :blk Motions.findCharBackward(primary_sel, buffer, ch);
            }
        };

        // Check if motion succeeded
        if (new_sel.head.eql(primary_sel.head)) {
            self.messages.add("Character not found", .error_msg) catch {};
            return;
        }

        // Update find/till state for repeat commands
        if (forward) {
            self.find_till_state = if (till)
                Motions.FindTillState.tillForward(ch)
            else
                Motions.FindTillState.findForward(ch);
        } else {
            self.find_till_state = if (till)
                Motions.FindTillState.tillBackward(ch)
            else
                Motions.FindTillState.findBackward(ch);
        }

        // Apply motion based on current mode
        if (self.getMode() == .select) {
            try self.selections.setSingleSelection(self.allocator, new_sel);
        } else {
            try self.selections.setSingleCursor(self.allocator, new_sel.head);
        }
    }

    /// Complete set mark command with user-provided register
    ///
    /// Sets a mark at the current cursor position in the specified register.
    /// Marks store both position and buffer_id, enabling cross-file jumps.
    /// Invalid register names (outside a-z, A-Z) show error message but don't crash.
    fn completeSetMark(self: *Editor, register: u8) !void {
        const cursor_pos = self.getCursorPosition();
        const buffer_id = self.buffer_manager.active_buffer_id orelse return error.NoActiveBuffer;

        self.marks.setMark(register, cursor_pos, buffer_id) catch |err| {
            const msg = switch (err) {
                error.InvalidMarkName => "Invalid mark name (use a-z, A-Z)",
                else => "Failed to set mark",
            };
            self.messages.add(msg, .error_msg) catch {};
            return;
        };

        const msg = try std.fmt.allocPrint(self.allocator, "Mark '{c}' set", .{register});
        defer self.allocator.free(msg);
        self.messages.add(msg, .info) catch {};
    }

    /// Complete goto mark command with user-provided register
    ///
    /// Jumps to the mark stored in the specified register.
    /// Automatically switches buffers if mark is in a different buffer,
    /// enabling seamless cross-file navigation (vim-like behavior).
    /// Unset marks show error message rather than causing crashes.
    fn completeGotoMark(self: *Editor, register: u8) !void {
        const mark = self.marks.getMark(register) orelse {
            const msg = try std.fmt.allocPrint(self.allocator, "Mark '{c}' not set", .{register});
            defer self.allocator.free(msg);
            self.messages.add(msg, .error_msg) catch {};
            return;
        };

        // Switch to the buffer if needed
        if (mark.buffer_id != self.buffer_manager.active_buffer_id) {
            self.buffer_manager.active_buffer_id = mark.buffer_id;
        }

        // Move cursor to mark position
        try self.selections.setSingleCursor(self.allocator, mark.position);

        const msg = try std.fmt.allocPrint(self.allocator, "Jumped to mark '{c}'", .{register});
        defer self.allocator.free(msg);
        self.messages.add(msg, .info) catch {};
    }

    /// Complete record macro command with user-provided register
    ///
    /// Starts recording a macro to the specified register.
    fn completeRecordMacro(self: *Editor, register: u8) !void {
        self.macro_recorder.startRecording(register) catch |err| {
            const msg = switch (err) {
                error.InvalidRegister => "Invalid register (use a-z)",
                error.AlreadyRecording => "Already recording a macro",
            };
            self.messages.add(msg, .error_msg) catch {};
            return;
        };

        const msg = try std.fmt.allocPrint(self.allocator, "Recording macro to '{c}'", .{register});
        defer self.allocator.free(msg);
        self.messages.add(msg, .info) catch {};
    }

    /// Complete play macro command with user-provided register
    ///
    /// Plays back the macro stored in the specified register.
    /// Deserializes command names from register text (one per line),
    /// then executes each command sequentially. Empty or missing registers
    /// show error messages. Command failures are reported but don't halt execution
    /// of remaining commands (vim-like graceful degradation).
    fn completePlayMacro(self: *Editor, register: u8) !void {
        const reg_id = Registers.RegisterId{ .named = register };
        const content = self.registers.get(reg_id) orelse {
            const msg = try std.fmt.allocPrint(self.allocator, "Register '{c}' is empty", .{register});
            defer self.allocator.free(msg);
            self.messages.add(msg, .error_msg) catch {};
            return;
        };

        // Deserialize and execute macro commands
        self.macro_recorder.deserializeCommands(content.text) catch {
            self.messages.add("Failed to load macro", .error_msg) catch {};
            return;
        };

        const commands = self.macro_recorder.getCommands();
        if (commands.len == 0) {
            self.messages.add("Empty macro", .error_msg) catch {};
            return;
        }

        // Execute each command in the macro
        for (commands) |cmd| {
            var ctx = Command.Context{ .editor = self };
            const result = self.command_registry.execute(cmd.name, &ctx);

            switch (result) {
                .success => {},
                .error_msg => |msg| {
                    // Show error but continue execution
                    self.messages.add(msg, .error_msg) catch {};
                },
            }
        }

        const msg = try std.fmt.allocPrint(self.allocator, "Played macro from '{c}'", .{register});
        defer self.allocator.free(msg);
        self.messages.add(msg, .info) catch {};
    }

    /// Complete replace character command with user-provided character
    ///
    /// Replaces the character at the cursor with the specified character.
    /// Uses delete+insert pattern because actions.zig provides no dedicated
    /// replaceCharAt function. This achieves the same result while reusing
    /// existing, well-tested primitives.
    ///
    /// Cursor position is preserved (vim 'r' command doesn't move cursor).
    fn completeReplaceChar(self: *Editor, ch: u8) !void {
        const buffer_id = self.buffer_manager.active_buffer_id orelse return error.NoActiveBuffer;
        const buffer = self.buffer_manager.getBufferMut(buffer_id) orelse return error.NoActiveBuffer;
        const primary_sel = self.selections.primary(self.allocator) orelse return error.NoSelection;

        // Delete character at cursor
        _ = Actions.deleteChar(buffer, primary_sel) catch {
            self.messages.add("Failed to delete character", .error_msg) catch {};
            return;
        };

        // Insert new character at same position
        const char_str = &[_]u8{ch};
        _ = Actions.insertText(buffer, primary_sel, char_str) catch {
            self.messages.add("Failed to insert character", .error_msg) catch {};
            return;
        };

        // In vim, 'r' command doesn't move the cursor
        // No cursor movement needed
    }

    pub const StatusInfo = struct {
        mode: Mode.Mode,
        buffer_name: []const u8,
        file_path: ?[]const u8,
        modified: bool,
        readonly: bool,
        line: usize,
        col: usize,
        total_lines: usize,
        percent: usize,
        selection_count: usize,
        can_undo: bool,
        can_redo: bool,
    };
};

test "editor: init and deinit" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try std.testing.expectEqual(Mode.Mode.normal, editor.getMode());
}

test "editor: create buffer" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();
    try std.testing.expect(editor.getActiveBuffer() != null);
}

test "editor: mode transitions" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.enterInsertMode();
    try std.testing.expectEqual(Mode.Mode.insert, editor.getMode());

    try editor.enterNormalMode();
    try std.testing.expectEqual(Mode.Mode.normal, editor.getMode());
}

test "editor: get status info" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();

    const info = editor.getStatusInfo();
    try std.testing.expectEqual(Mode.Mode.normal, info.mode);
    try std.testing.expectEqual(@as(usize, 1), info.selection_count);
}

// === Prompt System Tests ===

test "PendingCommand: isWaiting returns false for none" {
    const pc = PendingCommand.none;
    try std.testing.expect(!pc.isWaiting());
}

test "PendingCommand: isWaiting returns true for find_char" {
    const pc = PendingCommand{ .find_char = .{ .forward = true, .till = false } };
    try std.testing.expect(pc.isWaiting());
}

test "PendingCommand: isWaiting returns true for all variants" {
    const variants = [_]PendingCommand{
        .set_mark,
        .goto_mark,
        .record_macro,
        .play_macro,
        .replace_char,
    };

    for (variants) |pc| {
        try std.testing.expect(pc.isWaiting());
    }
}

test "completeFindChar: forward find success" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer with known content
    try editor.newBuffer();
    const buffer_id = editor.buffer_manager.active_buffer_id.?;
    const buffer = editor.buffer_manager.getBufferMut(buffer_id).?;
    try buffer.rope.setText("abcxyz");

    // Start at position 0
    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 0 });

    // Execute find char 'x' forward
    try editor.completeFindChar('x', true, false);

    // Verify cursor moved to 'x' at column 3
    const pos = editor.getCursorPosition();
    try std.testing.expectEqual(@as(usize, 0), pos.line);
    try std.testing.expectEqual(@as(usize, 3), pos.col);

    // Verify find_till_state was updated
    try std.testing.expect(editor.find_till_state.char != null);
    try std.testing.expectEqual(@as(u8, 'x'), editor.find_till_state.char.?);
}

test "completeFindChar: backward find success" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup buffer
    try editor.newBuffer();
    const buffer_id = editor.buffer_manager.active_buffer_id.?;
    const buffer = editor.buffer_manager.getBufferMut(buffer_id).?;
    try buffer.rope.setText("abcxyz");

    // Start at end
    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 5 });

    // Execute find char 'x' backward
    try editor.completeFindChar('x', false, false);

    // Verify cursor moved to 'x'
    const pos = editor.getCursorPosition();
    try std.testing.expectEqual(@as(usize, 3), pos.col);
}

test "completeFindChar: character not found" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();
    const buffer_id = editor.buffer_manager.active_buffer_id.?;
    const buffer = editor.buffer_manager.getBufferMut(buffer_id).?;
    try buffer.rope.setText("abcdef");

    // Start at position 0
    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 0 });

    // Execute find char 'x' (doesn't exist)
    try editor.completeFindChar('x', true, false);

    // Verify cursor didn't move
    const pos = editor.getCursorPosition();
    try std.testing.expectEqual(@as(usize, 0), pos.col);
}

test "completeFindChar: till forward stops before char" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();
    const buffer_id = editor.buffer_manager.active_buffer_id.?;
    const buffer = editor.buffer_manager.getBufferMut(buffer_id).?;
    try buffer.rope.setText("abcxyz");

    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 0 });

    // Execute till char 'x' (should stop at column 2, before 'x')
    try editor.completeFindChar('x', true, true);

    const pos = editor.getCursorPosition();
    try std.testing.expectEqual(@as(usize, 2), pos.col);
}

test "completeSetMark: valid register" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();
    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 5 });

    // Set mark 'a'
    try editor.completeSetMark('a');

    // Verify mark was set
    const mark = editor.marks.getMark('a');
    try std.testing.expect(mark != null);
    try std.testing.expectEqual(@as(usize, 5), mark.?.position.col);
}

test "completeSetMark: invalid register shows error" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();

    // Try to set mark with invalid register (number)
    try editor.completeSetMark('1');

    // Verify no crash occurred (error was handled gracefully)
    // Note: We can't easily verify the error message without exposing messages.items
}

test "completeGotoMark: jump to existing mark" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();
    const buffer_id = editor.buffer_manager.active_buffer_id.?;

    // Set mark at position 10
    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 10 });
    try editor.marks.setMark('a', .{ .line = 0, .col = 10 }, buffer_id);

    // Move to different position
    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 0 });

    // Jump to mark
    try editor.completeGotoMark('a');

    // Verify cursor moved to mark
    const pos = editor.getCursorPosition();
    try std.testing.expectEqual(@as(usize, 10), pos.col);
}

test "completeGotoMark: unset mark shows error" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();

    // Try to jump to unset mark
    try editor.completeGotoMark('z');

    // Verify no crash (error handled gracefully)
}

test "completeRecordMacro: valid register starts recording" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Start recording
    try editor.completeRecordMacro('a');

    // Verify recording started
    try std.testing.expect(editor.macro_recorder.isRecording());
    try std.testing.expectEqual(@as(?u8, 'a'), editor.macro_recorder.getRecordingRegister());
}

test "completeRecordMacro: invalid register shows error" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Try to record with invalid register
    try editor.completeRecordMacro('1');

    // Verify recording didn't start
    try std.testing.expect(!editor.macro_recorder.isRecording());
}

test "completePlayMacro: empty register shows error" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();

    // Try to play empty register
    try editor.completePlayMacro('z');

    // Verify no crash (error handled gracefully)
}

test "completeReplaceChar: replaces character at cursor" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();
    const buffer_id = editor.buffer_manager.active_buffer_id.?;
    const buffer = editor.buffer_manager.getBufferMut(buffer_id).?;
    try buffer.rope.setText("abcdef");

    // Position cursor at 'a'
    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 0 });

    // Replace 'a' with 'X'
    try editor.completeReplaceChar('X');

    // Verify text was replaced
    const text = try buffer.rope.toString(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.startsWith(u8, text, "Xbcdef"));
}

test "handlePendingCommandInput: escape cancels pending command" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();

    // Set pending command
    editor.pending_command = PendingCommand{ .find_char = .{ .forward = true, .till = false } };
    editor.prompt.show("Test:", .character);

    // Press escape
    try editor.handlePendingCommandInput(Keymap.Key{ .special = .escape });

    // Verify pending command was cleared
    try std.testing.expect(!editor.pending_command.isWaiting());
}

test "handlePendingCommandInput: special keys ignored" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();

    // Set pending command
    editor.pending_command = PendingCommand{ .find_char = .{ .forward = true, .till = false } };

    // Press arrow key (should be ignored)
    try editor.handlePendingCommandInput(Keymap.Key{ .special = .arrow_right });

    // Verify still waiting for input
    try std.testing.expect(editor.pending_command.isWaiting());
}

test "handlePendingCommandInput: character dispatches to handler" {
    const allocator = std.testing.allocator;
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    try editor.newBuffer();
    const buffer_id = editor.buffer_manager.active_buffer_id.?;
    const buffer = editor.buffer_manager.getBufferMut(buffer_id).?;
    try buffer.rope.setText("abcxyz");

    // Set pending find_char command
    editor.pending_command = PendingCommand{ .find_char = .{ .forward = true, .till = false } };
    try editor.selections.setSingleCursor(allocator, .{ .line = 0, .col = 0 });

    // Send character 'x'
    try editor.handlePendingCommandInput(Keymap.Key{ .char = 'x' });

    // Verify command completed and cursor moved
    try std.testing.expect(!editor.pending_command.isWaiting());
    const pos = editor.getCursorPosition();
    try std.testing.expectEqual(@as(usize, 3), pos.col);
}
