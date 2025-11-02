# Aesop Plugin System

The Aesop plugin system allows extending editor functionality through hooks and callbacks.

## Architecture

Plugins are registered at compile-time and hook into editor events through a vtable-based interface.

### Plugin Lifecycle

```
Plugin Init → Register with Manager → Event Hooks Called → Plugin Deinit
```

### Available Hooks

| Hook | Signature | When Called | Return Value |
|------|-----------|-------------|--------------|
| `on_buffer_open` | `fn(state, buffer_id: usize) !void` | After buffer is opened | N/A |
| `on_buffer_save` | `fn(state, buffer_id: usize) !void` | After buffer is saved | N/A |
| `on_buffer_close` | `fn(state, buffer_id: usize) !void` | Before buffer is closed | N/A |
| `on_key_press` | `fn(state, key: u21) !bool` | On every key press | `true` if handled |
| `on_mode_change` | `fn(state, old: u8, new: u8) !void` | When editor mode changes | N/A |

## Creating a Plugin

### 1. Define Plugin State

```zig
const MyPlugin = struct {
    allocator: std.mem.Allocator,
    // Your plugin state here
    counter: usize,
};
```

### 2. Implement Lifecycle Functions

```zig
pub fn init(allocator: std.mem.Allocator) !*anyopaque {
    const self = try allocator.create(MyPlugin);
    self.* = .{
        .allocator = allocator,
        .counter = 0,
    };
    return self;
}

pub fn deinit(state: *anyopaque) void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    self.allocator.destroy(self);
}
```

### 3. Implement Event Hooks

```zig
pub fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
    const self: *MyPlugin = @ptrCast(@alignCast(state));
    self.counter += 1;
    std.debug.print("Buffer {} opened. Total: {}\n", .{buffer_id, self.counter});
}

pub fn onKeyPress(state: *anyopaque, key: u21) !bool {
    const self: *MyPlugin = @ptrCast(@alignCast(state));

    // Handle specific key
    if (key == '@') {
        std.debug.print("Special key pressed!\n", .{});
        return true; // Key consumed, don't pass to editor
    }

    return false; // Let editor handle the key
}
```

### 4. Define VTable

```zig
pub const vtable = Plugin.VTable{
    .init = init,
    .deinit = deinit,
    .on_buffer_open = onBufferOpen,
    .on_key_press = onKeyPress,
    // Other hooks are optional
};
```

### 5. Create Factory Function

```zig
pub fn createPlugin(allocator: std.mem.Allocator) !*Plugin {
    const state = try MyPlugin.init(allocator);
    const plugin = try allocator.create(Plugin);
    plugin.* = .{
        .name = "myplugin",
        .version = "1.0.0",
        .description = "My awesome plugin",
        .vtable = &MyPlugin.vtable,
        .state = state,
    };
    return plugin;
}
```

## Example Plugins

### Auto-Complete Pairs Plugin

Automatically closes brackets, quotes, and parentheses:

```zig
// src/plugin/examples/autocomplete.zig
pub fn onKeyPress(state: *anyopaque, key: u21) !bool {
    const pairs = .{
        .{ '(', ')' },
        .{ '[', ']' },
        .{ '{', '}' },
    };

    inline for (pairs) |pair| {
        if (key == pair[0]) {
            // Insert closing character
            return true;
        }
    }

    return false;
}
```

### Logger Plugin

Logs all editor events to a file:

```zig
// src/plugin/examples/logger.zig
pub fn onBufferOpen(state: *anyopaque, buffer_id: usize) !void {
    const self: *LoggerPlugin = @ptrCast(@alignCast(state));
    const timestamp = std.time.milliTimestamp();
    try self.log_file.writer().print("[{}] Buffer opened: {}\n", .{timestamp, buffer_id});
}
```

## Plugin Registration

### Compile-Time Registration

Edit `src/plugin/loader.zig` to register your plugin:

```zig
const registry = [_]PluginEntry{
    .{ .name = "autocomplete", .factory = @import("examples/autocomplete.zig").createPlugin },
    .{ .name = "logger", .factory = @import("examples/logger.zig").createPlugin },
    .{ .name = "myplugin", .factory = @import("myplugin.zig").createPlugin }, // Add here
};
```

### Loading Plugins

Plugins are automatically loaded at editor startup:

```zig
// In editor initialization
try plugin_loader.loadAllPlugins(allocator, &editor.plugin_manager);
```

## Best Practices

### Memory Management
- Always allocate plugin state with the provided allocator
- Clean up all resources in `deinit()`
- Avoid global state

### Event Handling
- `on_key_press`: Return `true` only if you consumed the key
- Keep hook implementations fast (they're called frequently)
- Use buffering for I/O operations

### Error Handling
- Hooks can return errors - they'll be logged but won't crash the editor
- Prefer graceful degradation over crashing

### Thread Safety
- Plugins run on the main thread
- No concurrency primitives needed

## Plugin Ideas

- **Git integration**: Show git status in gutter
- **Snippet expansion**: Expand abbreviations
- **Code formatter**: Auto-format on save
- **Project search**: Ripgrep integration
- **Session management**: Save/restore editor state
- **Minimap**: Code overview sidebar
- **Terminal**: Embedded terminal
- **REPL**: Interactive evaluation
- **Debugger**: GDB/LLDB integration

## Limitations

- Plugins are compiled into the binary (no dynamic loading yet)
- No async/await support (but event loops work)
- Limited UI capabilities (no custom windows yet)
- Buffer API is read-only from plugins

## Future Enhancements

- Dynamic plugin loading (.so/.dll)
- Plugin marketplace/registry
- Hot reloading for development
- Custom UI components
- Inter-plugin communication
- Plugin configuration files
- Scripting language integration (Lua?)

## Troubleshooting

### Plugin Not Loading

1. Check that factory function is registered in `loader.zig`
2. Verify vtable has required `init` and `deinit` functions
3. Check for compilation errors in plugin code

### Plugin Crashes Editor

1. Ensure proper type casting in hooks (`@ptrCast(@alignCast(state))`)
2. Verify memory is allocated/freed correctly
3. Check for null pointer dereferences
4. Use error returns instead of panics

### Key Press Not Handled

1. Return `true` from `on_key_press` to consume key
2. Check that hook is registered in vtable
3. Verify plugin is enabled in manager

## Contributing Plugins

To contribute a plugin to the Aesop repository:

1. Create plugin in `src/plugin/examples/your_plugin.zig`
2. Add comprehensive tests
3. Document configuration options
4. Submit PR with example usage

## License

Plugins inherit the same license as Aesop unless otherwise specified.
