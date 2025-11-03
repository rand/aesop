# Aesop API Documentation

**Version**: 0.9.0-alpha
**Last Updated**: November 3, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Plugin System](#plugin-system)
3. [Core APIs](#core-apis)
4. [Extension Points](#extension-points)
5. [Examples](#examples)
6. [Best Practices](#best-practices)

---

## Overview

Aesop provides several extension points for customizing and extending functionality:

- **Plugin System**: Hook-based architecture for event handling
- **Command Registry**: Add custom commands to the palette
- **Keymap System**: Define custom key bindings
- **Configuration**: Extend with custom settings

### Extension Philosophy

Aesop's API design follows these principles:

1. **Hook-based**: React to editor events without modifying core
2. **Opt-in**: Plugins explicitly declare hooks they handle
3. **Non-blocking**: Hooks should execute quickly to avoid UI lag
4. **Type-safe**: Zig's type system ensures correctness
5. **Composable**: Multiple plugins can coexist

---

## Plugin System

The plugin system is Aesop's primary extension mechanism.

### Plugin Interface

Every plugin must implement the `Plugin` interface:

```zig
pub const Plugin = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    vtable: *const VTable,
    state: *anyopaque,

    pub const VTable = struct {
        init: *const fn (allocator: std.mem.Allocator) anyerror!*anyopaque,
        deinit: *const fn (state: *anyopaque) void,
        on_buffer_open: ?*const fn (state: *anyopaque, buffer_id: usize) anyerror!void,
        on_buffer_save: ?*const fn (state: *anyopaque, buffer_id: usize) anyerror!void,
        on_buffer_close: ?*const fn (state: *anyopaque, buffer_id: usize) anyerror!void,
        on_key_press: ?*const fn (state: *anyopaque, key: u21) anyerror!bool,
        on_mode_change: ?*const fn (state: *anyopaque, old_mode: u8, new_mode: u8) anyerror!void,
    };
};
```

### Available Hooks

| Hook | When Fired | Parameters | Return |
|------|-----------|------------|--------|
| `init` | Plugin loaded | `allocator` | `*anyopaque` state |
| `deinit` | Plugin unloaded | `state` | void |
| `on_buffer_open` | Buffer opened | `state`, `buffer_id` | void |
| `on_buffer_save` | Buffer saved | `state`, `buffer_id` | void |
| `on_buffer_close` | Buffer closed | `state`, `buffer_id` | void |
| `on_key_press` | Key pressed | `state`, `key: u21` | `bool` (consumed?) |
| `on_mode_change` | Mode changed | `state`, `old_mode`, `new_mode` | void |

### Hook Details

#### `init`

**Purpose**: Initialize plugin state

**Called**: When plugin is registered

**Example**:
```zig
pub fn init(allocator: std.mem.Allocator) !*anyopaque {
    const self = try allocator.create(MyPlugin);
    self.* = .{
        .allocator = allocator,
        .enabled = true,
        .data = null,
    };
    return self;
}
```

**Best Practices**:
- Allocate persistent state
- Open resources (files, sockets)
- Initialize data structures
- Handle errors gracefully

#### `deinit`

**Purpose**: Clean up plugin state

**Called**: When plugin is unregistered or editor exits

**Example**:
```zig
pub fn deinit(state: *anyopaque) void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    if (self.data) |data| {
        self.allocator.free(data);
    }
    self.allocator.destroy(self);
}
```

**Best Practices**:
- Free all allocated memory
- Close resources (files, sockets)
- Clean up gracefully
- Don't leak resources

#### `on_buffer_open`

**Purpose**: React to buffer opening

**Called**: When user opens a file or creates a new buffer

**Example**:
```zig
pub fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    try self.trackBuffer(buffer_id);
}
```

**Use Cases**:
- Track open buffers
- Initialize buffer-specific state
- Start file watchers
- Log buffer access

#### `on_buffer_save`

**Purpose**: React to buffer save

**Called**: When user saves a file (`:w`)

**Example**:
```zig
pub fn onBufferSave(state: *anyopaque, buffer_id: usize) !void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    try self.runFormatter(buffer_id);
}
```

**Use Cases**:
- Auto-formatting
- Linting
- Git integration (auto-commit)
- Backup creation
- Analytics

#### `on_buffer_close`

**Purpose**: React to buffer closing

**Called**: When buffer is closed (`:q`, `:bd`)

**Example**:
```zig
pub fn onBufferClose(state: *anyopaque, buffer_id: usize) !void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    try self.cleanupBuffer(buffer_id);
}
```

**Use Cases**:
- Clean up buffer-specific resources
- Stop file watchers
- Save buffer metadata
- Update buffer lists

#### `on_key_press`

**Purpose**: Intercept key presses

**Called**: Before normal key handling

**Return**: `true` if key consumed (stop propagation), `false` otherwise

**Example**:
```zig
pub fn onKeyPress(state: *anyopaque, key: u21) !bool {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    if (key == 'x' and self.intercept_mode) {
        try self.handleSpecialKey();
        return true; // Consume key, don't pass to editor
    }
    return false; // Pass to editor
}
```

**Use Cases**:
- Custom key bindings
- Vim-style operators
- Special input modes
- Keyboard macros

**Warning**: Returning `true` prevents normal key handling. Use carefully!

#### `on_mode_change`

**Purpose**: React to mode transitions

**Called**: When editor mode changes (Normal → Insert, etc.)

**Example**:
```zig
pub fn onModeChange(state: *anyopaque, old_mode: u8, new_mode: u8) !void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    if (new_mode == MODE_INSERT) {
        try self.startCompletionEngine();
    } else {
        try self.stopCompletionEngine();
    }
}
```

**Use Cases**:
- Start/stop background services
- Update UI indicators
- Log mode transitions
- Enable/disable features per mode

**Mode Constants**:
```zig
const MODE_NORMAL = 0;
const MODE_INSERT = 1;
const MODE_SELECT = 2;
const MODE_COMMAND = 3;
```

---

## Creating a Plugin

### Step 1: Define Plugin State

```zig
const MyPlugin = struct {
    allocator: std.mem.Allocator,
    enabled: bool,
    data: ?[]const u8,
    event_count: usize,
};
```

### Step 2: Implement Lifecycle Functions

```zig
pub fn init(allocator: std.mem.Allocator) !*anyopaque {
    const self = try allocator.create(MyPlugin);
    self.* = .{
        .allocator = allocator,
        .enabled = true,
        .data = null,
        .event_count = 0,
    };
    return self;
}

pub fn deinit(state: *anyopaque) void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    if (self.data) |data| {
        self.allocator.free(data);
    }
    self.allocator.destroy(self);
}
```

### Step 3: Implement Hook Functions

```zig
pub fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    self.event_count += 1;
    std.debug.print("Buffer {} opened (event #{})\n", .{ buffer_id, self.event_count });
}
```

### Step 4: Create VTable

```zig
pub const vtable = Plugin.VTable{
    .init = init,
    .deinit = deinit,
    .on_buffer_open = onBufferOpen,
    .on_buffer_save = null, // Not handling this hook
    .on_buffer_close = null,
    .on_key_press = null,
    .on_mode_change = null,
};
```

### Step 5: Export Plugin Factory

```zig
pub fn createPlugin(allocator: std.mem.Allocator) !*Plugin {
    const state = try MyPlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "my_plugin",
        .version = "1.0.0",
        .description = "My custom plugin",
        .vtable = &MyPlugin.vtable,
        .state = state,
    };
    return plugin;
}
```

---

## Core APIs

### Buffer API

**Location**: `src/buffer/rope.zig`

```zig
pub const Rope = struct {
    pub fn init(allocator: std.mem.Allocator) Rope;
    pub fn deinit(self: *Rope) void;

    // Text operations
    pub fn insert(self: *Rope, pos: usize, text: []const u8) !void;
    pub fn delete(self: *Rope, start: usize, end: usize) !void;
    pub fn slice(self: *const Rope, start: usize, end: usize) ![]const u8;
    pub fn len(self: *const Rope) usize;

    // Iteration
    pub fn iterator(self: *const Rope) Iterator;
    pub fn lines(self: *const Rope) LineIterator;
};
```

**Usage**:
```zig
var rope = Rope.init(allocator);
defer rope.deinit();

try rope.insert(0, "Hello, World!");
const text = try rope.slice(0, rope.len());
```

### Editor API

**Location**: `src/editor/editor.zig`

```zig
pub const Editor = struct {
    pub fn init(allocator: std.mem.Allocator) !Editor;
    pub fn deinit(self: *Editor) void;

    // Buffer management
    pub fn openBuffer(self: *Editor, path: []const u8) !usize;
    pub fn closeBuffer(self: *Editor, buffer_id: usize) !void;
    pub fn saveBuffer(self: *Editor, buffer_id: usize) !void;

    // Cursor operations
    pub fn moveCursor(self: *Editor, direction: Direction) void;
    pub fn getCursorPosition(self: *const Editor) Position;

    // Editing
    pub fn insertText(self: *Editor, text: []const u8) !void;
    pub fn deleteText(self: *Editor, count: usize) !void;
};
```

### Command API

**Location**: `src/editor/command.zig`

```zig
pub const CommandRegistry = struct {
    pub fn register(self: *CommandRegistry, name: []const u8, handler: CommandHandler) !void;
    pub fn execute(self: *CommandRegistry, name: []const u8, args: []const []const u8) !void;
    pub fn list(self: *const CommandRegistry) []const []const u8;
};

pub const CommandHandler = *const fn (editor: *Editor, args: []const []const u8) anyerror!void;
```

**Usage**:
```zig
fn myCommand(editor: *Editor, args: []const []const u8) !void {
    // Command implementation
}

try registry.register("my_command", myCommand);
```

### Configuration API

**Location**: `src/config/config.zig`

```zig
pub const Config = struct {
    pub fn load(allocator: std.mem.Allocator) !Config;
    pub fn save(self: *const Config) !void;

    // Settings access
    pub fn getBool(self: *const Config, key: []const u8) ?bool;
    pub fn getInt(self: *const Config, key: []const u8) ?i64;
    pub fn getString(self: *const Config, key: []const u8) ?[]const u8;

    pub fn setBool(self: *Config, key: []const u8, value: bool) !void;
    pub fn setInt(self: *Config, key: []const u8, value: i64) !void;
    pub fn setString(self: *Config, key: []const u8, value: []const u8) !void;
};
```

---

## Extension Points

### 1. Custom Commands

Add commands to the command palette:

```zig
const CommandRegistry = @import("editor/command.zig").CommandRegistry;

fn formatDocument(editor: *Editor, args: []const []const u8) !void {
    const buffer = editor.currentBuffer();
    // Format buffer content
}

pub fn registerCommands(registry: *CommandRegistry) !void {
    try registry.register("format_document", formatDocument);
}
```

### 2. Custom Key Bindings

Define custom key mappings:

```zig
const Keymap = @import("editor/keymap.zig").Keymap;

pub fn registerKeybindings(keymap: *Keymap) !void {
    try keymap.bind(.Normal, "Space f", "file_finder");
    try keymap.bind(.Normal, "Space p", "command_palette");
}
```

### 3. Custom Syntax Highlighting

Add tree-sitter queries for new languages:

**File**: `queries/mylang/highlights.scm`
```scheme
; Keywords
[
  "fn"
  "let"
  "return"
] @keyword

; Function calls
(call_expression
  function: (identifier) @function.call)
```

### 4. LSP Integration

Extend LSP support for new languages:

```zig
pub fn registerLanguageServer(manager: *LSPManager) !void {
    try manager.register("mylang", .{
        .command = "mylang-lsp",
        .args = &[_][]const u8{"--stdio"},
        .root_markers = &[_][]const u8{".mylang-project"},
    });
}
```

---

## Examples

### Example 1: Event Logger Plugin

**File**: `src/plugin/examples/logger.zig`

```zig
const std = @import("std");
const Plugin = @import("../system.zig").Plugin;

pub const LoggerPlugin = struct {
    allocator: std.mem.Allocator,
    log_file: ?std.fs.File,
    event_count: usize,

    pub fn init(allocator: std.mem.Allocator) !*anyopaque {
        const self = try allocator.create(LoggerPlugin);
        self.* = .{
            .allocator = allocator,
            .log_file = try std.fs.cwd().createFile("/tmp/aesop-events.log", .{}),
            .event_count = 0,
        };
        return self;
    }

    pub fn deinit(state: *anyopaque) void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        if (self.log_file) |file| file.close();
        self.allocator.destroy(self);
    }

    pub fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
        const self: *LoggerPlugin = @ptrCast(@alignCast(state));
        const file = self.log_file orelse return;
        try file.writer().print("[BUFFER_OPEN] id={}\n", .{buffer_id});
        self.event_count += 1;
    }

    pub const vtable = Plugin.VTable{
        .init = init,
        .deinit = deinit,
        .on_buffer_open = onBufferOpen,
        .on_buffer_save = null,
        .on_buffer_close = null,
        .on_key_press = null,
        .on_mode_change = null,
    };
};

pub fn createPlugin(allocator: std.mem.Allocator) !*Plugin {
    const state = try LoggerPlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "logger",
        .version = "1.0.0",
        .description = "Logs editor events",
        .vtable = &LoggerPlugin.vtable,
        .state = state,
    };
    return plugin;
}
```

**Usage**:
```zig
const logger = try createPlugin(allocator);
try plugin_manager.register(logger);
// Events now logged to /tmp/aesop-events.log
```

### Example 2: Auto-Formatter Plugin

```zig
pub const FormatterPlugin = struct {
    allocator: std.mem.Allocator,
    enabled: bool,

    pub fn init(allocator: std.mem.Allocator) !*anyopaque {
        const self = try allocator.create(FormatterPlugin);
        self.* = .{
            .allocator = allocator,
            .enabled = true,
        };
        return self;
    }

    pub fn deinit(state: *anyopaque) void {
        const self: *FormatterPlugin = @ptrCast(@alignCast(state));
        self.allocator.destroy(self);
    }

    pub fn onBufferSave(state: *anyopaque, buffer_id: usize) !void {
        const self: *FormatterPlugin = @ptrCast(@alignCast(state));
        if (!self.enabled) return;

        // Run formatter on buffer before save
        // (Implementation would call external formatter)
        std.debug.print("Formatting buffer {}\n", .{buffer_id});
    }

    pub const vtable = Plugin.VTable{
        .init = init,
        .deinit = deinit,
        .on_buffer_open = null,
        .on_buffer_save = onBufferSave,
        .on_buffer_close = null,
        .on_key_press = null,
        .on_mode_change = null,
    };
};
```

### Example 3: Mode Indicator Plugin

```zig
pub const ModeIndicatorPlugin = struct {
    allocator: std.mem.Allocator,
    current_mode: []const u8,

    pub fn init(allocator: std.mem.Allocator) !*anyopaque {
        const self = try allocator.create(ModeIndicatorPlugin);
        self.* = .{
            .allocator = allocator,
            .current_mode = "NORMAL",
        };
        return self;
    }

    pub fn deinit(state: *anyopaque) void {
        const self: *ModeIndicatorPlugin = @ptrCast(@alignCast(state));
        self.allocator.destroy(self);
    }

    pub fn onModeChange(state: *anyopaque, old_mode: u8, new_mode: u8) !void {
        const self: *ModeIndicatorPlugin = @ptrCast(@alignCast(state));
        self.current_mode = switch (new_mode) {
            0 => "NORMAL",
            1 => "INSERT",
            2 => "SELECT",
            3 => "COMMAND",
            else => "UNKNOWN",
        };
        std.debug.print("Mode: {} → {s}\n", .{ old_mode, self.current_mode });
    }

    pub const vtable = Plugin.VTable{
        .init = init,
        .deinit = deinit,
        .on_buffer_open = null,
        .on_buffer_save = null,
        .on_buffer_close = null,
        .on_key_press = null,
        .on_mode_change = onModeChange,
    };
};
```

---

## Best Practices

### Plugin Development

1. **Keep hooks fast**: Hooks run in the main event loop. Avoid blocking operations.
2. **Handle errors**: Use `try` and proper error handling. Don't crash the editor.
3. **Clean up resources**: Always free memory and close files in `deinit`.
4. **Use allocators**: Accept allocator parameter, don't use global allocator.
5. **Document hooks**: Clearly document which hooks your plugin uses.

### Memory Management

```zig
// ✅ Good: Clean memory management
pub fn init(allocator: std.mem.Allocator) !*anyopaque {
    const self = try allocator.create(MyPlugin);
    errdefer allocator.destroy(self);

    self.data = try allocator.alloc(u8, 1024);
    return self;
}

pub fn deinit(state: *anyopaque) void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    self.allocator.free(self.data);
    self.allocator.destroy(self);
}
```

### Error Handling

```zig
// ✅ Good: Graceful error handling
pub fn onBufferSave(state: *anyopaque, buffer_id: usize) !void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));

    self.formatBuffer(buffer_id) catch |err| {
        std.debug.print("Warning: Format failed: {}\n", .{err});
        return; // Don't propagate error, allow save to continue
    };
}
```

### Hook Return Values

```zig
// ✅ Good: Only consume key when actually handled
pub fn onKeyPress(state: *anyopaque, key: u21) !bool {
    const self: *MyPlugin = @ptrCast(@alignCast(state));

    if (key == 'x' and self.special_mode) {
        try self.handleKey();
        return true; // Consumed
    }

    return false; // Not consumed, pass to editor
}
```

### State Management

```zig
// ✅ Good: Type-safe state casting
pub fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    // Use self safely
}
```

### Testing Plugins

```zig
test "plugin lifecycle" {
    const allocator = std.testing.allocator;

    const state = try MyPlugin.init(allocator);
    defer MyPlugin.deinit(state);

    const self: *MyPlugin = @ptrCast(@alignCast(state));
    try std.testing.expectEqual(true, self.enabled);
}

test "plugin hooks" {
    const allocator = std.testing.allocator;
    const state = try MyPlugin.init(allocator);
    defer MyPlugin.deinit(state);

    try MyPlugin.onBufferOpen(state, 1);

    const self: *MyPlugin = @ptrCast(@alignCast(state));
    try std.testing.expectEqual(@as(usize, 1), self.event_count);
}
```

---

## API Versioning

**Current API Version**: 1.0

**Stability**: Alpha (subject to change)

**Compatibility**: Aesop 0.9.x plugins may need updates for 1.0 release

**Deprecation Policy**: Breaking changes announced in release notes

---

## Future API Additions

Planned extension points for future releases:

- **Completion providers**: Custom completion sources
- **Diagnostic providers**: Custom lint/check integration
- **Snippet providers**: Custom snippet expansion
- **Git integration hooks**: Version control events
- **UI customization**: Custom status line, gutter elements
- **Async hooks**: Long-running operations without blocking
- **IPC communication**: Plugin-to-plugin messaging

---

## Getting Help

- **Source code**: `src/plugin/` directory
- **Examples**: `src/plugin/examples/`
- **Issues**: GitHub issue tracker
- **Documentation**: This file and inline comments

---

**Happy hacking!**
