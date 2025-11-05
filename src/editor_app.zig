//! Working editor application
//! Integrates all components into a functional text editor

const std = @import("std");
const build_options = @import("build_options");
const Editor = @import("editor/editor.zig").Editor;
const Cursor = @import("editor/cursor.zig");
const renderer_mod = @import("render/renderer.zig");
const Renderer = renderer_mod.Renderer;
const Attrs = renderer_mod.Attrs;
const Cell = renderer_mod.Cell;
const statusline = @import("render/statusline.zig");
const messageline = @import("render/messageline.zig");
const keyhints = @import("render/keyhints.zig");
const contextbar = @import("render/contextbar.zig");
const paletteline = @import("render/paletteline.zig");
const filefinderline = @import("render/filefinderline.zig");
const filetree = @import("render/filetree.zig");
const completionline = @import("render/completion.zig");
const bufferswitcher = @import("render/bufferswitcher.zig");
const gutter = @import("render/gutter.zig");
const input_mod = @import("terminal/input.zig");
const Keymap = @import("editor/keymap.zig");
// Conditionally import tree-sitter or stub based on build configuration
const TreeSitter = if (build_options.enable_treesitter)
    @import("editor/treesitter.zig")
else
    @import("editor/treesitter_stub.zig");
const commandline = @import("editor/commandline.zig");

/// Get configuration file path using XDG Base Directory specification
/// Priority:
/// 1. $XDG_CONFIG_HOME/aesop/config.conf
/// 2. ~/.config/aesop/config.conf
/// 3. ./aesop.conf (current directory)
fn getConfigPath(allocator: std.mem.Allocator) !?[]const u8 {
    // Try XDG_CONFIG_HOME first
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg_config_home| {
        defer allocator.free(xdg_config_home);
        const path = try std.fs.path.join(allocator, &[_][]const u8{ xdg_config_home, "aesop", "config.conf" });
        // Check if file exists
        if (std.fs.accessAbsolute(path, .{})) |_| {
            return path;
        } else |_| {
            allocator.free(path);
            // Fall through to next option
        }
    } else |_| {}

    // Try ~/.config/aesop/config.conf
    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        const path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "aesop", "config.conf" });
        // Check if file exists
        if (std.fs.accessAbsolute(path, .{})) |_| {
            return path;
        } else |_| {
            allocator.free(path);
            // Fall through to current directory
        }
    } else |_| {}

    // Try ./aesop.conf in current directory
    std.fs.cwd().access("aesop.conf", .{}) catch {
        // No config file found - return null to use defaults
        return null;
    };
    return try allocator.dupe(u8, "aesop.conf");
}

/// Editor application
pub const EditorApp = struct {
    editor: Editor,
    renderer: Renderer,
    allocator: std.mem.Allocator,
    running: bool,
    gutter_config: gutter.GutterConfig,
    mouse_drag_start: ?Cursor.Position,
    syntax_parser: ?TreeSitter.Parser,
    command_buffer: std.ArrayList(u8), // Command line input buffer (for :q, :w, etc.)

    /// Initialize editor application
    pub fn init(allocator: std.mem.Allocator) !EditorApp {
        var editor = try Editor.init(allocator);
        errdefer editor.deinit();

        // Load configuration from file (if it exists)
        const Config = @import("editor/config.zig").Config;
        const config_path = try getConfigPath(allocator);
        defer if (config_path) |path| allocator.free(path);

        const config = if (config_path) |path|
            Config.loadFromFile(allocator, path) catch |err| blk: {
                // If file doesn't exist or can't be read, use defaults
                if (err == error.FileNotFound) {
                    break :blk Config.init(allocator);
                }
                return err;
            }
        else
            Config.init(allocator);

        editor.config.deinit();
        editor.config = config;

        var renderer = try Renderer.init(allocator);
        errdefer renderer.deinit();

        // Initialize gutter config from editor config
        const gutter_cfg = gutter.GutterConfig{
            .show_line_numbers = editor.config.line_numbers,
            .line_number_style = if (editor.config.relative_line_numbers)
                .relative
            else
                .absolute,
            .show_git_status = false, // TODO: Future feature
            .show_diagnostics = true, // Enable diagnostic icons in gutter
            .width = 5,
        };

        var app = EditorApp{
            .editor = editor,
            .renderer = renderer,
            .allocator = allocator,
            .running = false,
            .gutter_config = gutter_cfg,
            .mouse_drag_start = null,
            .syntax_parser = null,
            .command_buffer = .{}, // Unmanaged ArrayList
        };

        // Install signal handlers for terminal cleanup on crash
        app.installSignalHandlers();

        return app;
    }

    /// Clean up
    pub fn deinit(self: *EditorApp) void {
        if (self.syntax_parser) |*parser| {
            parser.deinit();
        }
        self.command_buffer.deinit(self.allocator);
        self.editor.deinit();
        self.renderer.deinit();
    }

    /// Signal handler for SIGINT and SIGTERM
    fn signalHandler(sig: i32) callconv(.c) void {
        _ = sig;
        // Emergency cleanup - restore terminal state
        renderer_mod.emergencyCleanup();
        // Exit immediately
        std.process.exit(130); // 128 + SIGINT(2)
    }

    /// Install signal handlers for cleanup on crash/kill
    fn installSignalHandlers(self: *EditorApp) void {
        _ = self;

        const posix = std.posix;

        // Create sigaction structure for our handler
        var act = posix.Sigaction{
            .handler = .{ .handler = signalHandler },
            .mask = posix.sigemptyset(),
            .flags = 0,
        };

        // Install handler for SIGINT (Ctrl+C)
        posix.sigaction(posix.SIG.INT, &act, null);

        // Install handler for SIGTERM (kill command)
        posix.sigaction(posix.SIG.TERM, &act, null);
    }

    /// Get or create parser for current buffer
    fn ensureParser(self: *EditorApp) !void {
        // Get active buffer
        const buffer = self.editor.getActiveBuffer() orelse return;

        // Determine language from buffer name
        const buffer_name = buffer.metadata.getName();
        const language = TreeSitter.Language.fromFilename(buffer_name);

        // If we have a parser and it's for the right language, keep it
        if (self.syntax_parser) |existing| {
            if (existing.language == language) {
                return;
            }
            // Wrong language - cleanup and recreate
            var parser = self.syntax_parser.?;
            parser.deinit();
        }

        // Create new parser for this language
        std.debug.print("Creating parser for buffer '{s}', detected language: {s}\n", .{ buffer_name, language.getName() });
        self.syntax_parser = try TreeSitter.Parser.init(self.allocator, language);
        std.debug.print("Parser created successfully\n", .{});
    }

    /// Run the editor
    pub fn run(self: *EditorApp, filepath: ?[]const u8) !void {
        // Load file or create empty buffer
        if (filepath) |path| {
            try self.editor.openFile(path);
        } else {
            try self.editor.newBuffer();
        }

        // Enter raw mode
        try self.renderer.enterRawMode();
        defer self.renderer.exitRawMode() catch {};

        self.running = true;

        // Main event loop
        var input_buf: [64]u8 = undefined;
        var parser = input_mod.Parser{};

        while (self.running) {
            // Render
            try self.render();

            // Process input
            const n = try self.renderer.terminal.readInput(&input_buf);
            if (n > 0) {
                const events = try parser.parse(self.allocator, input_buf[0..n]);
                defer self.allocator.free(events);

                for (events) |event| {
                    try self.handleEvent(event);
                }
            }

            // Small sleep to avoid busy loop
            std.Thread.sleep(5 * std.time.ns_per_ms);
        }
    }

    /// Handle input event
    fn handleEvent(self: *EditorApp, event: input_mod.Event) !void {
        // Handle palette input separately
        if (self.editor.palette.visible) {
            try self.handlePaletteInput(event);
            return;
        }

        // Handle file finder input separately
        if (self.editor.file_finder.visible) {
            try self.handleFileFinderInput(event);
            return;
        }

        // Handle file tree input (when visible, intercept navigation keys)
        if (self.editor.file_tree.visible) {
            const handled = try self.handleFileTreeInput(event);
            if (handled) return;
            // If not handled, fall through to normal input
        }

        // Handle buffer switcher input separately
        if (self.editor.buffer_switcher_visible) {
            try self.handleBufferSwitcherInput(event);
            return;
        }

        // Handle command mode input separately
        if (self.editor.getMode() == .command) {
            try self.handleCommandInput(event);
            return;
        }

        switch (event) {
            .char => |c| {
                // Convert to keymap key
                const key = Keymap.Key{ .char = c.codepoint };

                // Check for command mode entry (: in normal mode)
                if (c.codepoint == ':' and !c.mods.ctrl and !c.mods.alt and
                    self.editor.getMode() == .normal)
                {
                    try self.editor.enterCommandMode();
                    try self.command_buffer.resize(self.allocator, 0); // Clear buffer
                    return;
                }

                // Check for quit command (Ctrl+Q in normal mode)
                if (c.mods.ctrl and c.codepoint == 'q' and
                    self.editor.getMode() == .normal)
                {
                    self.running = false;
                    return;
                }

                // Process through editor
                try self.editor.processKey(key);
            },

            .key => |k| {
                // Convert special key to keymap key
                const key = Keymap.Key{ .special = k.key };

                // Escape always returns to normal mode
                if (k.key == .escape) {
                    try self.editor.enterNormalMode();
                    return;
                }

                // Process through editor
                try self.editor.processKey(key);
            },

            .resize => |r| {
                try self.renderer.handleResize();
                _ = r;
            },

            .mouse => |m| {
                std.debug.print("Mouse event received: kind={}, row={}, col={}\n", .{ m.kind, m.row, m.col });
                try self.handleMouse(m);
            },

            else => {},
        }
    }

    /// Handle palette input
    fn handlePaletteInput(self: *EditorApp, event: input_mod.Event) !void {
        switch (event) {
            .char => |c| {
                // Add character to query
                try self.editor.palette.addChar(c.codepoint);
            },

            .key => |k| {
                switch (k.key) {
                    .escape => {
                        // Close palette
                        self.editor.palette.hide();
                    },
                    .backspace => {
                        // Remove last character
                        self.editor.palette.backspace();
                    },
                    .enter => {
                        // Execute selected command
                        try self.executePaletteCommand();
                    },
                    .up => {
                        // Move selection up
                        self.editor.palette.selectPrevious();
                    },
                    .down => {
                        // Move selection down
                        const matches = try self.editor.palette.filterCommands(&self.editor.command_registry, self.allocator);
                        defer self.allocator.free(matches);
                        self.editor.palette.selectNext(matches.len);
                    },
                    else => {},
                }
            },

            else => {},
        }
    }

    /// Execute the currently selected palette command
    fn executePaletteCommand(self: *EditorApp) !void {
        const matches = try self.editor.palette.filterCommands(&self.editor.command_registry, self.allocator);
        defer self.allocator.free(matches);

        if (matches.len == 0) return;

        const selected_idx = @min(self.editor.palette.selected_index, matches.len - 1);
        const command_name = matches[selected_idx].name;

        // Hide palette
        self.editor.palette.hide();

        // Record command execution for history
        self.editor.palette.recordExecution(command_name) catch {};

        // Execute command
        var ctx = @import("editor/command.zig").Context{ .editor = &self.editor };
        const result = self.editor.command_registry.execute(command_name, &ctx);

        switch (result) {
            .success => {},
            .error_msg => |msg| {
                self.editor.messages.add(msg, .error_msg) catch {};
            },
        }
    }

    /// Handle file finder input
    fn handleFileFinderInput(self: *EditorApp, event: input_mod.Event) !void {
        switch (event) {
            .char => |c| {
                // Add character to query
                try self.editor.file_finder.addChar(c.codepoint);
            },

            .key => |k| {
                switch (k.key) {
                    .escape => {
                        // Close file finder
                        self.editor.file_finder.hide();
                    },
                    .backspace => {
                        // Remove last character
                        self.editor.file_finder.backspace();
                    },
                    .enter => {
                        // Open selected file
                        try self.executeFileFinderSelection();
                    },
                    .up => {
                        // Move selection up
                        self.editor.file_finder.selectPrevious();
                    },
                    .down => {
                        // Move selection down
                        const matches = try self.editor.file_finder.filterFiles(self.allocator);
                        defer self.allocator.free(matches);
                        self.editor.file_finder.selectNext(matches.len);
                    },
                    else => {},
                }
            },

            else => {},
        }
    }

    /// Execute the currently selected file finder selection (open file)
    fn executeFileFinderSelection(self: *EditorApp) !void {
        const matches = try self.editor.file_finder.filterFiles(self.allocator);
        defer self.allocator.free(matches);

        if (matches.len == 0) return;

        const selected_idx = @min(self.editor.file_finder.selected_index, matches.len - 1);
        const file_path = matches[selected_idx].path;

        // Hide file finder
        self.editor.file_finder.hide();

        // Open the selected file
        self.editor.openFile(file_path) catch |err| {
            const msg = try std.fmt.allocPrint(self.allocator, "Failed to open file: {s}", .{@errorName(err)});
            defer self.allocator.free(msg);
            self.editor.messages.add(msg, .error_msg) catch {};
        };
    }

    /// Handle file tree input - returns true if handled
    fn handleFileTreeInput(self: *EditorApp, event: input_mod.Event) !bool {
        switch (event) {
            .key => |k| {
                switch (k.key) {
                    .down, .up => {
                        // Navigate tree
                        if (k.key == .down) {
                            self.editor.file_tree.selectNext();
                        } else {
                            self.editor.file_tree.selectPrevious();
                        }
                        return true;
                    },
                    .enter => {
                        // Open file or toggle directory
                        const node = self.editor.file_tree.getSelected() orelse return true;

                        if (node.is_dir) {
                            try self.editor.file_tree.toggleSelected();
                        } else {
                            // Open the file
                            self.editor.openFile(node.path) catch |err| {
                                const msg = try std.fmt.allocPrint(self.allocator, "Failed to open file: {s}", .{@errorName(err)});
                                defer self.allocator.free(msg);
                                self.editor.messages.add(msg, .error_msg) catch {};
                                return true; // Stay in file tree on error
                            };
                            // Successfully opened file - hide the file tree
                            self.editor.file_tree.visible = false;
                        }
                        return true;
                    },
                    else => {},
                }
            },
            .char => |c| {
                // Handle j/k for vim-style navigation
                if (c.codepoint == 'j') {
                    self.editor.file_tree.selectNext();
                    return true;
                } else if (c.codepoint == 'k') {
                    self.editor.file_tree.selectPrevious();
                    return true;
                }
            },
            else => {},
        }

        // Not handled, allow normal processing
        return false;
    }

    /// Handle buffer switcher input
    fn handleBufferSwitcherInput(self: *EditorApp, event: input_mod.Event) !void {
        switch (event) {
            .key => |k| {
                switch (k.key) {
                    .escape => {
                        // Close buffer switcher
                        self.editor.buffer_switcher_visible = false;
                        self.editor.buffer_switcher_selected = 0;
                    },
                    .enter => {
                        // Switch to selected buffer
                        try self.executeBufferSwitcherSelection();
                    },
                    .up => {
                        // Move selection up
                        if (self.editor.buffer_switcher_selected > 0) {
                            self.editor.buffer_switcher_selected -= 1;
                        }
                    },
                    .down => {
                        // Move selection down
                        const buffer_count = self.editor.buffer_manager.count();
                        if (self.editor.buffer_switcher_selected + 1 < buffer_count) {
                            self.editor.buffer_switcher_selected += 1;
                        }
                    },
                    else => {},
                }
            },

            else => {},
        }
    }

    /// Execute the currently selected buffer switcher selection (switch buffer)
    fn executeBufferSwitcherSelection(self: *EditorApp) !void {
        const buffers = try bufferswitcher.getBufferList(&self.editor, self.allocator);
        defer self.allocator.free(buffers);

        if (buffers.len == 0) return;

        const selected_idx = @min(self.editor.buffer_switcher_selected, buffers.len - 1);
        const buffer_id = buffers[selected_idx].id;

        // Hide buffer switcher
        self.editor.buffer_switcher_visible = false;
        self.editor.buffer_switcher_selected = 0;

        // Switch to the selected buffer
        try self.editor.buffer_manager.switchTo(buffer_id);
    }

    /// Handle command mode input
    fn handleCommandInput(self: *EditorApp, event: input_mod.Event) !void {
        switch (event) {
            .char => |c| {
                // Ignore control characters except specific ones
                if (c.mods.ctrl) return;

                // Add character to command buffer
                const char_bytes = &[_]u8{@intCast(c.codepoint)};
                try self.command_buffer.appendSlice(self.allocator, char_bytes);
            },

            .key => |k| {
                switch (k.key) {
                    .escape => {
                        // Cancel command and return to normal mode
                        try self.command_buffer.resize(self.allocator, 0);
                        try self.editor.enterNormalMode();
                    },
                    .backspace => {
                        // Remove last character
                        if (self.command_buffer.items.len > 0) {
                            _ = self.command_buffer.pop();
                        }
                    },
                    .enter => {
                        // Execute command
                        try self.executeCommand();
                    },
                    else => {},
                }
            },

            else => {},
        }
    }

    /// Execute the command in command_buffer
    fn executeCommand(self: *EditorApp) !void {
        const cmd_text = self.command_buffer.items;

        // Parse command
        const cmd = try commandline.parse(self.allocator, cmd_text);
        defer commandline.deinit(cmd, self.allocator);

        // Clear command buffer and return to normal mode
        try self.command_buffer.resize(self.allocator, 0);
        try self.editor.enterNormalMode();

        // Execute command
        if (cmd.shouldQuit()) {
            if (cmd == .quit and cmd.quit.force) {
                // Force quit
                self.running = false;
            } else {
                // Check if buffer is modified
                const buffer = self.editor.getActiveBuffer();
                const is_modified = if (buffer) |buf| buf.metadata.modified else false;

                if (is_modified and !cmd.quit.force) {
                    const msg = "No write since last change (use :q! to force)";
                    try self.editor.messages.add(msg, .error_msg);
                } else {
                    self.running = false;
                }
            }
        }

        if (cmd.shouldWrite()) {
            // Save file - need mutable buffer
            const active_id = self.editor.buffer_manager.active_buffer_id orelse return;
            const buffer = self.editor.buffer_manager.getBufferMut(active_id) orelse return;

            const save_path = switch (cmd) {
                .write => |w| w.path,
                .write_quit => |wq| wq.path,
                else => null,
            };

            if (save_path) |path| {
                // Save to specified path
                try buffer.saveAs(path);
            } else {
                // Save to current file
                if (buffer.metadata.filepath) |_| {
                    try buffer.save();
                } else {
                    const msg = "No file name (use :w <filename>)";
                    try self.editor.messages.add(msg, .error_msg);
                    return;
                }
            }

            const msg = try std.fmt.allocPrint(self.allocator, "Saved {s}", .{buffer.metadata.getName()});
            defer self.allocator.free(msg);
            try self.editor.messages.add(msg, .info);
        }

        if (cmd == .edit) {
            // Open new file
            try self.editor.openFile(cmd.edit.path);
        }

        if (cmd == .unknown) {
            if (cmd.unknown.len > 0) {
                const msg = try std.fmt.allocPrint(self.allocator, "Unknown command: {s}", .{cmd.unknown});
                defer self.allocator.free(msg);
                try self.editor.messages.add(msg, .error_msg);
            }
        }
    }

    /// Handle mouse events
    fn handleMouse(self: *EditorApp, mouse: anytype) !void {
        switch (mouse.kind) {
            .press_left => {
                try self.handleMousePress(mouse.row, mouse.col);
            },
            .move => {
                // Treat move as drag if we have a drag start position
                try self.handleMouseDrag(mouse.row, mouse.col);
            },
            .release => {
                self.handleMouseRelease();
            },
            .scroll_up => {
                self.handleMouseScroll(-3); // Scroll up 3 lines
            },
            .scroll_down => {
                self.handleMouseScroll(3); // Scroll down 3 lines
            },
            else => {},
        }
    }

    /// Handle mouse scroll
    fn handleMouseScroll(self: *EditorApp, delta: isize) void {
        if (delta < 0) {
            const abs_delta: usize = @intCast(@abs(delta));
            self.editor.scroll_offset -|= abs_delta;
        } else {
            const buffer = self.editor.getActiveBuffer() orelse return;
            const size = self.renderer.getSize();
            const total_lines = buffer.lineCount();
            const viewport_height: usize = size.height -| 2;
            const max_scroll = if (total_lines > viewport_height) total_lines - viewport_height else 0;

            self.editor.scroll_offset = @min(self.editor.scroll_offset + @as(usize, @intCast(delta)), max_scroll);
        }
    }

    /// Handle mouse press - start selection
    fn handleMousePress(self: *EditorApp, screen_row: u16, screen_col: u16) !void {
        const size = self.renderer.getSize();
        const buffer = self.editor.getActiveBuffer() orelse return;

        // Check if we have a message displayed
        const has_message = self.editor.messages.current() != null;
        const reserved_lines: usize = if (has_message) 2 else 1;

        // Ignore clicks on status/message lines
        if (screen_row >= size.height - reserved_lines) return;

        const viewport = self.editor.getViewport(size.height - reserved_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Calculate file tree offset
        const tree_offset: u16 = if (self.editor.file_tree.visible)
            self.editor.file_tree.width + 1 // +1 for separator
        else
            0;

        // Handle clicks in file tree
        if (self.editor.file_tree.visible and screen_col < self.editor.file_tree.width) {
            try self.handleFileTreeClick(screen_row);
            return;
        }

        // Ignore clicks on file tree separator
        if (screen_col < tree_offset) return;

        // Ignore clicks in gutter
        const gutter_end = tree_offset + gutter_width;
        if (screen_col < gutter_end) return;

        // Convert screen position to buffer position (accounting for file tree and horizontal scroll)
        const buffer_line = viewport.start_line + screen_row;
        const buffer_col = (screen_col - gutter_end) + self.editor.col_offset;

        // Clamp to valid buffer position
        const total_lines = buffer.lineCount();
        if (buffer_line >= total_lines) return;

        // Create position
        const pos = Cursor.Position{
            .line = buffer_line,
            .col = buffer_col,
        };

        // Start drag tracking
        self.mouse_drag_start = pos;

        // Set cursor position
        try self.editor.selections.setSingleCursor(self.allocator, pos);

        // Return to normal mode if in visual mode
        if (self.editor.getMode() == .select) {
            try self.editor.enterNormalMode();
        }
    }

    /// Handle mouse drag - extend selection
    fn handleMouseDrag(self: *EditorApp, screen_row: u16, screen_col: u16) !void {
        const drag_start = self.mouse_drag_start orelse return;

        const size = self.renderer.getSize();
        const buffer = self.editor.getActiveBuffer() orelse return;

        // Check if we have a message displayed
        const has_message = self.editor.messages.current() != null;
        const reserved_lines: usize = if (has_message) 2 else 1;

        // Ignore drags on status/message lines
        if (screen_row >= size.height - reserved_lines) return;

        const viewport = self.editor.getViewport(size.height - reserved_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Calculate file tree offset
        const tree_offset: u16 = if (self.editor.file_tree.visible)
            self.editor.file_tree.width + 1 // +1 for separator
        else
            0;

        // Ignore drags in file tree
        if (screen_col < tree_offset) return;

        // Ignore drags in gutter
        const gutter_end = tree_offset + gutter_width;
        if (screen_col < gutter_end) return;

        // Convert screen position to buffer position (accounting for file tree and horizontal scroll)
        const buffer_line = viewport.start_line + screen_row;
        const buffer_col = (screen_col - gutter_end) + self.editor.col_offset;

        // Clamp to valid buffer position
        const total_lines = buffer.lineCount();
        if (buffer_line >= total_lines) return;

        // Create drag end position
        const drag_end = Cursor.Position{
            .line = buffer_line,
            .col = buffer_col,
        };

        // Enter select mode if not already
        if (self.editor.getMode() != .select) {
            try self.editor.enterSelectMode();
        }

        // Create selection from drag start to drag end
        const selection = Cursor.Selection{
            .anchor = drag_start,
            .head = drag_end,
        };

        try self.editor.selections.setSingleSelection(self.allocator, selection);
    }

    /// Handle mouse release - finalize selection
    fn handleMouseRelease(self: *EditorApp) void {
        self.mouse_drag_start = null;
    }

    /// Handle mouse click in file tree
    fn handleFileTreeClick(self: *EditorApp, screen_row: u16) !void {
        if (!self.editor.file_tree.visible) return;

        const size = self.renderer.getSize();

        // Check if we have a message displayed
        const has_message = self.editor.messages.current() != null;
        const reserved_lines: usize = if (has_message) 2 else 1;

        // File tree viewport height (total height minus status/message lines)
        const viewport_height: usize = if (size.height > reserved_lines)
            size.height - reserved_lines
        else
            0;

        // Calculate which file tree item was clicked
        const item_index = self.editor.file_tree.scroll_offset + screen_row;

        // Check if click is within valid range
        if (item_index >= self.editor.file_tree.flat_view.items.len) return;

        // Update selection
        self.editor.file_tree.selected_index = item_index;
        self.editor.file_tree.adjustScroll(viewport_height);

        // Get the clicked node
        const node = self.editor.file_tree.getSelected() orelse return;

        if (node.is_dir) {
            // Toggle directory expansion
            try self.editor.file_tree.toggleSelected();
        } else {
            // Open file
            try self.editor.openFile(node.path);
            // Optionally hide file tree after opening
            // self.editor.file_tree.hide();
        }
    }

    /// Check if context bar should be shown
    fn shouldShowContextBar(self: *EditorApp) bool {
        // Show context bar for:
        // - Palette/file finder/buffer switcher open
        // - Incremental search active
        // - Pending command waiting for input
        // - Empty buffers (welcome mode)

        return self.editor.palette.visible or
            self.editor.file_finder.visible or
            self.editor.buffer_switcher_visible or
            self.editor.search.incremental or
            self.editor.pending_command.isWaiting() or
            self.isEmptyBuffer();
    }

    /// Check if current buffer is empty
    fn isEmptyBuffer(self: *EditorApp) bool {
        const buffer = self.editor.getActiveBuffer() orelse return true;
        const line_count = buffer.lineCount();

        // Buffer is empty if it has 0 lines, or 1 line with no content
        if (line_count == 0) return true;
        if (line_count == 1) {
            const text = buffer.getText() catch return false;
            defer self.allocator.free(text);
            return text.len == 0 or (text.len == 1 and text[0] == '\n');
        }
        return false;
    }

    /// Render the editor
    fn render(self: *EditorApp) !void {
        // Clear screen
        self.renderer.clear();

        const size = self.renderer.getSize();

        // Check if we have a message to display
        const has_message = self.editor.messages.current() != null;

        // Calculate footer lines (status line + optional context bar)
        const needs_context_bar = self.shouldShowContextBar();
        const footer_lines: usize = if (needs_context_bar) 2 else 1;
        const message_lines: usize = if (has_message) 1 else 0;
        const reserved_lines: usize = footer_lines + message_lines;

        // Auto-adjust horizontal scroll to keep cursor visible
        // Calculate viewport width for text content
        const active_buffer = self.editor.getActiveBuffer();
        const gutter_width = if (active_buffer) |b| gutter.calculateWidth(self.gutter_config, b.lineCount()) else 0;
        const tree_width = if (self.editor.file_tree.visible) self.editor.file_tree.width + 1 else 0; // +1 for separator
        const viewport_width = size.width -| (gutter_width + tree_width);
        self.editor.adjustHorizontalScroll(viewport_width);

        // Render file tree FIRST (acts as background layer)
        // This prevents buffer text from rendering into file tree space
        try filetree.render(&self.renderer, &self.editor, size.height - reserved_lines, self.allocator);

        // Render buffer content (on top of file tree, within proper bounds)
        try self.renderBuffer(size.height -| reserved_lines);

        // Render gutter with diagnostics
        const viewport = self.editor.getViewport(size.height -| reserved_lines);
        const cursor_pos = self.editor.getCursorPosition();

        // Get file URI for diagnostic lookup
        const buffer = self.editor.getActiveBuffer();
        const file_uri = if (buffer) |buf| blk: {
            if (buf.metadata.filepath) |filepath| {
                break :blk self.editor.makeFileUri(filepath) catch null;
            }
            break :blk null;
        } else null;
        defer if (file_uri) |uri| self.allocator.free(uri);

        // Calculate gutter offset based on file tree visibility
        const gutter_col_offset: u16 = if (self.editor.file_tree.visible)
            self.editor.file_tree.width + 1 // +1 for separator
        else
            0;

        try gutter.renderWithDiagnostics(
            &self.renderer,
            self.gutter_config,
            viewport.start_line,
            viewport.end_line,
            cursor_pos.line,
            &self.editor.diagnostic_manager,
            file_uri,
            self.editor.getTheme(),
            gutter_col_offset,
        );

        // Render message line (if message exists)
        _ = try messageline.render(&self.renderer, &self.editor);

        // Render status line (or command line if in command mode)
        if (self.editor.getMode() == .command) {
            // Render command line
            const status_row = size.height - 1;

            // Clear status line
            var col: u16 = 0;
            while (col < size.width) : (col += 1) {
                self.renderer.output.setCell(status_row, col, .{
                    .char = ' ',
                    .fg = .default,
                    .bg = .default,
                    .attrs = .{},
                });
            }

            // Display command prompt with buffer contents
            const cmd_line = try std.fmt.allocPrint(self.allocator, ":{s}", .{self.command_buffer.items});
            defer self.allocator.free(cmd_line);

            self.renderer.writeText(
                status_row,
                0,
                cmd_line,
                .default,
                .default,
                .{},
                null, // Use full width for command line
            );
        } else {
            try statusline.render(&self.renderer, &self.editor);

            // Render key hints (overlays on status line)
            try keyhints.render(&self.renderer, &self.editor);
        }

        // Render context bar (if needed)
        if (needs_context_bar) {
            try contextbar.render(&self.renderer, &self.editor, self.isEmptyBuffer(), self.allocator);
        }

        // Render cursor (if not in overlay mode or command mode)
        if (!self.editor.palette.visible and
            !self.editor.file_finder.visible and
            !self.editor.buffer_switcher_visible and
            self.editor.getMode() != .command)
        {
            try self.renderCursor(size.height - reserved_lines);
        }

        // Render command palette (overlay on top of everything)
        try paletteline.render(&self.renderer, &self.editor, self.allocator);

        // Render file finder (overlay on top of everything)
        try filefinderline.render(&self.renderer, &self.editor, self.allocator);

        // Render completion popup (overlay on top of everything)
        try completionline.render(&self.renderer, &self.editor, &self.editor.completion_list);

        // Render hover popup (overlay on top of everything)
        if (self.editor.hover_content) |hover_text| {
            const popup = @import("render/popup.zig");
            const hover_cursor_pos = (self.editor.selections.primary(self.allocator) orelse return);
            const hover_cursor = hover_cursor_pos.head;

            // Calculate popup dimensions
            const config = popup.PopupConfig{
                .max_width = 60,
                .max_height = 15,
                .border = .single,
                .title = "Hover",
            };
            const dims = popup.calculateDimensions(hover_text, config);

            // Calculate position near cursor
            const position = popup.calculatePosition(
                size.width,
                size.height,
                @intCast(hover_cursor.line -| self.editor.scroll_offset),
                @intCast(hover_cursor.col),
                dims.width,
                dims.height,
            );

            // Render popup
            try popup.render(
                &self.renderer,
                position,
                dims.width,
                dims.height,
                hover_text,
                config,
            );
        }

        // Render buffer switcher (overlay on top of everything)
        try bufferswitcher.render(
            &self.renderer,
            &self.editor,
            self.allocator,
            self.editor.buffer_switcher_visible,
            self.editor.buffer_switcher_selected,
        );

        // Perform render
        try self.renderer.render();
    }

    /// Render all cursors
    fn renderCursor(self: *EditorApp, visible_lines: usize) !void {
        const buffer = self.editor.getActiveBuffer() orelse return;
        const viewport = self.editor.getViewport(visible_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Render all cursors from all selections
        const selections = self.editor.selections.all(self.allocator);
        for (selections) |sel| {
            const cursor_pos = sel.head;

            // Check if cursor is in viewport
            if (cursor_pos.line < viewport.start_line or cursor_pos.line >= viewport.end_line) {
                continue; // Cursor is off-screen
            }

            // Calculate screen position
            const screen_row = @as(u16, @intCast(cursor_pos.line - viewport.start_line));
            const screen_col = gutter_width + @as(u16, @intCast(cursor_pos.col));

            // Get current cell at cursor position or create empty cell
            const cell = self.renderer.output.getCell(screen_row, screen_col) orelse Cell{
                .char = ' ',
                .fg = .default,
                .bg = .default,
                .attrs = .{},
            };

            // Set cursor with reverse video
            self.renderer.output.setCell(screen_row, screen_col, .{
                .char = cell.char,
                .fg = cell.bg, // Swap colors for cursor
                .bg = cell.fg,
                .attrs = .{ .reverse = true },
            });
        }
    }

    /// Render buffer content
    fn renderBuffer(self: *EditorApp, visible_lines: usize) !void {
        const buffer = self.editor.getActiveBuffer() orelse return;
        const size = self.renderer.getSize();

        const viewport = self.editor.getViewport(visible_lines);
        const gutter_width = gutter.calculateWidth(self.gutter_config, buffer.lineCount());

        // Calculate buffer start column (accounting for file tree if visible)
        const buffer_start_col = if (self.editor.file_tree.visible)
            gutter_width + self.editor.file_tree.width + 1 // +1 for separator
        else
            gutter_width;

        // Calculate available viewport width for text (terminal width - start column)
        const text_max_width: u16 = size.width;

        // Get selection (for highlighting)
        const primary_sel = self.editor.selections.primary(self.allocator) orelse return;
        const in_visual_mode = self.editor.getMode() == .select and !primary_sel.isCollapsed();
        const sel_range = if (in_visual_mode) primary_sel.range() else null;

        // Get buffer text
        const text = try buffer.getText();
        defer self.allocator.free(text);

        // Get search matches (for highlighting)
        const search_matches = if (self.editor.search.active)
            try self.editor.search.findAll(text, self.allocator)
        else
            &[_]@import("editor/search.zig").Search.Match{};
        defer if (self.editor.search.active) self.allocator.free(search_matches);

        // Get syntax highlights (if enabled)
        const syntax_highlights = if (self.editor.config.syntax_highlighting) blk: {
            try self.ensureParser();
            if (self.syntax_parser) |*parser| {
                // Parse text to create syntax tree
                parser.parse(text) catch |err| {
                    std.debug.print("Parse failed: {}\n", .{err});
                    // If parsing fails, fall back to no highlights
                    break :blk &[_]TreeSitter.HighlightToken{};
                };
                break :blk try parser.getHighlights(text, viewport.start_line, viewport.end_line);
            }
            std.debug.print("No parser available\n", .{});
            break :blk &[_]TreeSitter.HighlightToken{};
        } else blk: {
            std.debug.print("Syntax highlighting disabled in config\n", .{});
            break :blk &[_]TreeSitter.HighlightToken{};
        };
        defer if (self.editor.config.syntax_highlighting and self.syntax_parser != null) self.allocator.free(syntax_highlights);

        // Simple line rendering (just display lines)
        var line_num: usize = viewport.start_line;
        var row: u16 = 0;
        var i: usize = 0;

        // Skip lines before viewport
        var current_line: usize = 0;
        while (i < text.len and current_line < viewport.start_line) {
            if (text[i] == '\n') {
                current_line += 1;
            }
            i += 1;
        }

        // Render visible lines
        while (i < text.len and line_num < viewport.end_line) {
            const line_start = i;
            var line_end = i;

            // Find end of line
            while (line_end < text.len and text[line_end] != '\n') {
                line_end += 1;
            }

            const line_text_full = text[line_start..line_end];

            // Apply horizontal scrolling: slice line text from col_offset
            const line_text = if (self.editor.col_offset < line_text_full.len)
                line_text_full[self.editor.col_offset..]
            else
                "";

            // Check if this line has selection or search matches
            const line_has_selection = if (sel_range) |range|
                (line_num >= range.start.line and line_num <= range.end.line)
            else
                false;

            const line_has_search = blk: {
                for (search_matches) |match| {
                    if (line_num >= match.start.line and line_num <= match.end.line) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            const line_has_syntax = blk: {
                for (syntax_highlights) |token| {
                    if (token.line == line_num) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (line_has_selection or line_has_search or line_has_syntax) {
                // Render line character by character with highlighting
                try self.renderLineWithHighlights(
                    row,
                    buffer_start_col,
                    line_text,
                    line_num,
                    self.editor.col_offset, // Pass col_offset for coordinate adjustment
                    sel_range,
                    search_matches,
                    syntax_highlights,
                    text, // Full text buffer for byte offset calculation
                    text_max_width,
                );
            } else {
                // Render line normally (with max width constraint)
                self.renderer.writeText(
                    row,
                    buffer_start_col,
                    line_text,
                    .default,
                    .default,
                    .{},
                    text_max_width,
                );
            }

            // Move to next line
            i = if (line_end < text.len) line_end + 1 else line_end;
            line_num += 1;
            row += 1;

            if (row >= visible_lines) break;
        }
    }

    /// Render a line with selection, search, and syntax highlighting
    /// Optimized: batches consecutive characters with the same style (10-100x faster)
    fn renderLineWithHighlights(
        self: *EditorApp,
        row: u16,
        start_col: u16,
        line_text: []const u8,
        line_num: usize,
        col_offset: usize, // Horizontal scroll offset - text already sliced, but coords need adjustment
        opt_sel_range: anytype,
        search_matches: []const @import("editor/search.zig").Search.Match,
        syntax_highlights: []const TreeSitter.HighlightToken,
        full_text: []const u8, // Full text buffer for byte offset calculation
        max_width: u16,
    ) !void {
        if (line_text.len == 0) return;

        // Style state for batching
        const StyleState = struct {
            is_selected: bool,
            is_search_match: bool,
            syntax_group: ?TreeSitter.HighlightGroup,

            fn eql(a: @This(), b: @This()) bool {
                return a.is_selected == b.is_selected and
                    a.is_search_match == b.is_search_match and
                    std.meta.eql(a.syntax_group, b.syntax_group);
            }
        };

        var col: usize = 0;
        var screen_col = start_col;
        var batch_start_col: usize = 0;
        var batch_start_screen_col: u16 = start_col;
        var current_style: ?StyleState = null;

        // Calculate byte offset for start of this line (once)
        var line_start_byte: usize = 0;
        var temp_line: usize = 0;
        for (full_text, 0..) |byte, idx| {
            if (temp_line == line_num) {
                line_start_byte = idx;
                break;
            }
            if (byte == '\n') {
                temp_line += 1;
            }
        }

        // Helper to flush current batch
        const flushBatch = struct {
            fn call(
                renderer: *renderer_mod.Renderer,
                r: u16,
                scr_col: u16,
                text: []const u8,
                style: StyleState,
                theme: anytype,
            ) void {
                if (text.len == 0) return;

                // Priority: selection > search match > syntax > normal
                if (style.is_selected) {
                    renderer.writeText(r, scr_col, text, .default, .default, Attrs{ .reverse = true }, null);
                } else if (style.is_search_match) {
                    renderer.writeText(r, scr_col, text, .default, .default, Attrs{ .underline = true }, null);
                } else if (style.syntax_group) |group| {
                    const color = group.toColor(theme);
                    renderer.writeText(r, scr_col, text, color, .default, Attrs{}, null);
                } else {
                    renderer.writeText(r, scr_col, text, .default, .default, Attrs{}, null);
                }
            }
        }.call;

        // Process each character, batching consecutive same-styled chars
        while (col < line_text.len and screen_col < max_width) {
            // Actual buffer column (accounting for horizontal scroll)
            const buffer_col = col + col_offset;

            // Check if character is in selection
            const is_selected = if (opt_sel_range) |range| blk: {
                if (line_num == range.start.line and line_num == range.end.line) {
                    break :blk buffer_col >= range.start.col and buffer_col < range.end.col;
                } else if (line_num == range.start.line) {
                    break :blk buffer_col >= range.start.col;
                } else if (line_num == range.end.line) {
                    break :blk buffer_col < range.end.col;
                } else if (line_num > range.start.line and line_num < range.end.line) {
                    break :blk true;
                } else {
                    break :blk false;
                }
            } else false;

            // Check if character is in search match (only if not selected)
            const is_search_match = if (!is_selected) blk: {
                for (search_matches) |match| {
                    if (line_num == match.start.line and line_num == match.end.line) {
                        if (buffer_col >= match.start.col and buffer_col < match.end.col) {
                            break :blk true;
                        }
                    } else if (line_num == match.start.line) {
                        if (buffer_col >= match.start.col) break :blk true;
                    } else if (line_num == match.end.line) {
                        if (buffer_col < match.end.col) break :blk true;
                    } else if (line_num > match.start.line and line_num < match.end.line) {
                        break :blk true;
                    }
                }
                break :blk false;
            } else false;

            // Check for syntax highlighting (only if not selected or search matched)
            const syntax_group: ?TreeSitter.HighlightGroup = if (!is_selected and !is_search_match) blk: {
                // Calculate byte offset of current character
                const byte_offset = line_start_byte + buffer_col;

                // Check if this byte_offset falls within any syntax token
                for (syntax_highlights) |token| {
                    if (byte_offset >= token.start_byte and byte_offset < token.end_byte) {
                        break :blk token.group;
                    }
                }
                break :blk null;
            } else null;

            const new_style = StyleState{
                .is_selected = is_selected,
                .is_search_match = is_search_match,
                .syntax_group = syntax_group,
            };

            // If style changed, flush previous batch and start new one
            if (current_style) |prev_style| {
                if (!prev_style.eql(new_style)) {
                    // Flush previous batch
                    const batch_text = line_text[batch_start_col..col];
                    flushBatch(&self.renderer, row, batch_start_screen_col, batch_text, prev_style, self.editor.getTheme());

                    // Start new batch
                    batch_start_col = col;
                    batch_start_screen_col = screen_col;
                    current_style = new_style;
                }
            } else {
                // First character - start batch
                current_style = new_style;
            }

            col += 1;
            screen_col += 1;
        }

        // Flush final batch
        if (current_style) |style| {
            const batch_text = line_text[batch_start_col..col];
            flushBatch(&self.renderer, row, batch_start_screen_col, batch_text, style, self.editor.getTheme());
        }
    }
};

/// Run editor application
pub fn runEditor(allocator: std.mem.Allocator, filepath: ?[]const u8) !void {
    var app = try EditorApp.init(allocator);
    defer app.deinit();

    try app.run(filepath);
}
