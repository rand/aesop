# Prompt System Architecture

## Overview

The prompt system enables commands to request user input without blocking the event loop. Commands that need additional parameters (like "find character 'x'" or "jump to mark 'a'") activate a prompt, return control to the event loop, and resume execution when input arrives.

This architecture separates command initiation from completion, avoiding inline blocking reads and maintaining the editor's responsiveness.

## Design Pattern: Command Continuation

### Problem

Modal editors have commands that need incremental input:
- **f{char}** - find character: command needs a character parameter
- **m{char}** - set mark: command needs a register name
- **@{char}** - play macro: command needs a macro register

Traditional approaches:
1. **Inline blocking read**: Breaks event loop, freezes editor during input
2. **Callback passing**: Clutters command registry with continuation functions
3. **Boolean flags**: One flag per command type, no type safety, hard to extend

### Solution: Continuation-Passing with Union State

```zig
pub const PendingCommand = union(enum) {
    none,
    find_char: struct { forward: bool, till: bool },
    set_mark,
    goto_mark,
    record_macro,
    play_macro,
    replace_char,
};
```

**Why this works**:
- **Type safety**: Enum payload encodes command-specific parameters
- **Single state variable**: `editor.pending_command` replaces multiple boolean flags
- **Centralized dispatch**: One handler (`handlePendingCommandInput`) routes to all completions
- **Clean extension**: New prompted commands add one enum variant, one completion handler

**Pattern flow**:
1. Command initiates: Set `pending_command`, show prompt, return
2. Event loop: Detects `pending_command.isWaiting()`, routes input to dispatcher
3. Dispatcher: Extracts input, calls appropriate completion handler
4. Completion: Executes action, clears `pending_command`, hides prompt

## State Machine

### Input Routing Priority

The event loop processes input in strict priority order:

```zig
pub fn processKey(self: *Editor, key: Keymap.Key) !void {
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

    // Priority 3: Normal command matching
    try self.keymap.processKey(key);
}
```

**Rationale**:
- Incremental search is transient modal state that overrides everything
- Pending commands capture single-character responses before normal command processing
- Normal commands only process when no higher-priority state is active

### State Transitions

```
IDLE STATE
    ↓ (user presses 'f')
COMMAND INITIATED
    pending_command = .find_char
    prompt.show("Find char:", .character)
    ↓ (return to event loop)
AWAITING INPUT
    ↓ (user presses 'x')
DISPATCH INPUT
    handlePendingCommandInput(key) → completeFindChar('x', ...)
    ↓
COMPLETE ACTION
    cursor moves to 'x'
    pending_command = .none
    prompt.hide()
    ↓
IDLE STATE
```

**Cancellation path**:
```
AWAITING INPUT
    ↓ (user presses Escape)
CANCEL
    pending_command = .none
    prompt.hide()
    ↓
IDLE STATE
```

### Concurrent State Handling

**Interaction with other systems**:
- **Search mode**: Takes precedence over pending commands (checked first in processKey)
- **Visual mode**: Pending commands can operate in visual mode (selection context preserved)
- **Insert mode**: Pending commands only activate from normal/visual mode

## Integration Points

### Command Registry (command.zig)

Commands that need input follow this pattern:

```zig
fn commandNeedingInput(ctx: *Context) Result {
    // Set pending state with parameters
    ctx.editor.pending_command = PendingCommand{
        .variant = .{ .param = value }
    };

    // Activate prompt
    ctx.editor.prompt.show("Prompt text:", .character);

    // Return immediately
    return Result.ok();
}
```

**Key points**:
- Command function only *initiates* the action
- No blocking, no input reading, no completion logic
- All state encoded in `pending_command` payload

### Completion Handlers (editor.zig)

Each pending command variant has a corresponding completion handler:

```zig
fn completeVariant(self: *Editor, input: u8) !void {
    // Validate input
    if (!isValidInput(input)) {
        self.messages.add("Invalid input", .error_msg) catch {};
        return;
    }

    // Execute action using input parameter
    try self.executeAction(input);

    // Update related state if needed
    self.some_state.update(input);

    // State cleanup handled by dispatcher
}
```

**Pattern details**:
- Handlers assume `pending_command` is cleared by dispatcher (don't clear it themselves)
- Handlers assume prompt is hidden by dispatcher (don't hide it themselves)
- Handlers focus solely on executing the action with the provided input
- Error handling: Show message, return early (dispatcher handles cleanup)

### Dispatcher (editor.zig)

Single entry point for all pending command input:

```zig
fn handlePendingCommandInput(self: *Editor, key: Keymap.Key) !void {
    // Handle universal escape
    if (key == .escape) {
        self.pending_command = .none;
        self.prompt.hide();
        return;
    }

    // Extract input character
    const char_byte = switch (key) {
        .char => |c| @as(u8, @intCast(c)),
        .special => return, // Ignore special keys
    };

    // Dispatch to completion handler
    switch (self.pending_command) {
        .none => unreachable,
        .variant => |params| {
            self.pending_command = .none;  // Clear state
            self.prompt.hide();             // Hide prompt
            try self.completeVariant(char_byte, params);
        },
        // ... other variants
    }

    self.ensureCursorVisible();
}
```

**Dispatcher responsibilities**:
- Universal escape handling (all pending commands can be cancelled)
- Input extraction and validation (convert Key to character byte)
- State cleanup (clear `pending_command`, hide prompt)
- Completion handler invocation
- Cursor visibility update

## Adding New Prompted Commands

To add a command that needs user input:

### 1. Add Variant to PendingCommand

In `src/editor/editor.zig`:

```zig
pub const PendingCommand = union(enum) {
    // ... existing variants

    /// New command: description of what it waits for
    new_command: struct {
        param1: bool,
        param2: SomeType,
    },
};
```

**Guidelines**:
- Variant name should be `snake_case` verb phrase
- Include doc comment explaining what input is expected
- Use struct payload for command-specific parameters
- Use unit payload (no struct) if no parameters needed

### 2. Add Completion Handler

In `src/editor/editor.zig`:

```zig
/// Complete new command with user input
///
/// Called after user provides character input for new_command.
/// Performs [description of action] using the input character.
fn completeNewCommand(self: *Editor, ch: u8, param1: bool, param2: SomeType) !void {
    // Validate input
    if (!isValid(ch)) {
        self.messages.add("Invalid input", .error_msg) catch {};
        return;
    }

    // Execute action
    try self.performAction(ch, param1, param2);

    // Update related state
    self.related_state.update(ch);
}
```

**Guidelines**:
- Name: `complete{CommandName}` in PascalCase
- Parameters: `self`, input character, then struct payload fields
- Don't clear `pending_command` or hide prompt (dispatcher handles this)
- Show error messages for invalid input, return early

### 3. Add Dispatcher Case

In `src/editor/editor.zig`, add to `handlePendingCommandInput`:

```zig
fn handlePendingCommandInput(self: *Editor, key: Keymap.Key) !void {
    // ... existing code

    switch (self.pending_command) {
        // ... existing cases

        .new_command => |params| {
            self.pending_command = .none;
            self.prompt.hide();
            try self.completeNewCommand(char_byte, params.param1, params.param2);
        },
    }
}
```

**Guidelines**:
- Always clear `pending_command` before calling handler
- Always hide prompt before calling handler
- Extract struct payload with `|params|` capture
- Pass parameters in same order as completion handler signature

### 4. Add Command Function

In `src/editor/command.zig`:

```zig
fn newCommand(ctx: *Context) Result {
    ctx.editor.pending_command = PendingCommand{
        .new_command = .{
            .param1 = computeParam1(ctx),
            .param2 = computeParam2(ctx),
        },
    };
    ctx.editor.prompt.show("Prompt message:", .character);
    return Result.ok();
}
```

**Guidelines**:
- Compute parameters from context before setting pending state
- Use appropriate prompt type (`.character`, `.text`, `.number`, `.choice`)
- Prompt message should clearly indicate what input is expected
- Return `Result.ok()` immediately after setting state

### 5. Register Command

In `src/editor/command.zig`, add to command registry:

```zig
pub fn init(allocator: std.mem.Allocator) !*Registry {
    // ... existing code

    try registry.register("new_command", &newCommand);
}
```

### 6. Add Keybinding

In `src/editor/keymap.zig`:

```zig
try keymap.bind(.normal, Key.char('n'), "new_command");
```

## Prompt Types

The prompt system supports multiple input types:

- `.character` - Single character input (most common for vim-style commands)
- `.text` - Full text input (for search, replace, file names)
- `.number` - Numeric input (for repeat counts, line numbers)
- `.choice` - Multiple choice selection (y/n confirmations)

Current implementation focuses on `.character` type for vim command completion.

## Error Handling

### Validation Patterns

Commands validate input at completion time:

```zig
fn completeSetMark(self: *Editor, register: u8) !void {
    // Validate register range
    if (register < 'a' or register > 'z') {
        self.messages.add("Mark must be a-z", .error_msg) catch {};
        return;
    }

    // Proceed with action
    try self.marks.set(register, position);
}
```

**Rationale**: Validation happens in completion handlers (not dispatcher) because validity rules are command-specific.

### Error Display

Invalid input shows error message but doesn't crash:

```zig
self.some_operation(input) catch {
    self.messages.add("Operation failed", .error_msg) catch {};
    return;  // Clean exit, state already cleared by dispatcher
};
```

**Rationale**: Dispatcher has already cleared state and hidden prompt before calling handler. Handler can safely return early on error.

## Testing Strategy

### Unit Tests

Test each completion handler in isolation:

```zig
test "completeFindChar: forward find" {
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup: buffer with known content
    try editor.buffer.setText("abcxyz");
    editor.cursor.moveTo(.{.line = 0, .col = 0});

    // Execute: complete find char 'x'
    try editor.completeFindChar('x', true, false);

    // Verify: cursor moved to 'x'
    try expectEqual(3, editor.cursor.position.col);
}
```

**Coverage targets**:
- Valid input: cursor moves correctly
- Invalid input: error message shown, cursor unchanged
- Edge cases: character not found, at end of line, wrapped search

### Integration Tests

Test full command flow from initiation to completion:

```zig
test "find char forward: full flow" {
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Setup: buffer with content
    try editor.buffer.setText("abcxyz");

    // Execute: press 'f' key
    try editor.processKey(Key.char('f'));

    // Verify: pending state set, prompt shown
    try expect(editor.pending_command == .find_char);
    try expect(editor.prompt.isActive());

    // Execute: press 'x' key
    try editor.processKey(Key.char('x'));

    // Verify: cursor moved, state cleared, prompt hidden
    try expectEqual(3, editor.cursor.position.col);
    try expect(editor.pending_command == .none);
    try expect(!editor.prompt.isActive());
}
```

**Coverage targets**:
- Full initiation → input → completion flow
- Escape cancellation at input stage
- Interaction with visual mode
- Interaction with counts (3fx finds third 'x')

### Edge Case Tests

```zig
test "pending command: escape cancels" {
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Start find char
    try editor.processKey(Key.char('f'));
    try expect(editor.pending_command == .find_char);

    // Press escape
    try editor.processKey(Key.special(.escape));

    // Verify: state cleared, no action taken
    try expect(editor.pending_command == .none);
    try expect(!editor.prompt.isActive());
}

test "pending command: special keys ignored" {
    var editor = try Editor.init(allocator);
    defer editor.deinit();

    // Start find char
    try editor.processKey(Key.char('f'));

    // Press arrow key (should be ignored)
    try editor.processKey(Key.special(.arrow_right));

    // Verify: still waiting for input
    try expect(editor.pending_command == .find_char);
    try expect(editor.prompt.isActive());
}
```

## Design Rationale

### Why Union over Booleans?

**Alternative considered**: Separate boolean flags
```zig
// DON'T DO THIS
waiting_for_find_char: bool = false,
waiting_for_mark: bool = false,
waiting_for_macro: bool = false,
find_char_forward: bool = false,
find_char_till: bool = false,
```

**Problems**:
- No mutual exclusion enforcement (multiple flags could be true)
- No type safety (forgot to check a flag = silent bug)
- Linear growth (N commands = N+ flags)
- Parameter passing unclear (where do params go?)

**Union benefits**:
- Compiler-enforced mutual exclusion (only one variant active)
- Exhaustive switch checking catches unhandled cases
- Parameters encoded in payload (type-safe, self-documenting)
- O(1) extension cost (new command = +1 variant)

### Why Centralized Dispatcher?

**Alternative considered**: Each command polls for input in event loop

**Problems**:
- Event loop becomes O(N) in number of prompted commands
- Command-specific input handling scattered across codebase
- Hard to enforce consistent cancellation (escape handling)
- Difficult to reason about priority when multiple systems want input

**Centralized dispatcher benefits**:
- Single point of truth for input routing
- Consistent escape handling for all commands
- Clear priority ordering (search > pending > normal)
- O(1) dispatch via switch statement

### Why Separate Initiation and Completion?

**Alternative considered**: Command function blocks until input arrives

**Problems**:
- Requires threading or coroutines (complex in Zig)
- Blocks event loop during input wait
- Can't cancel while waiting
- Can't render while waiting (frozen UI)

**Continuation pattern benefits**:
- Non-blocking: event loop stays responsive
- Composable: pending commands work in any mode
- Cancellable: escape always available
- Renderable: prompt updates shown immediately

## Future Extensions

### Multi-Character Input

For commands needing multi-character sequences (digraphs, Ex commands):

```zig
pub const PendingCommand = union(enum) {
    // ... existing

    ex_command: struct {
        buffer: [256]u8,
        len: usize,
    },
};
```

**Implementation**: Completion handler appends to buffer, returns without clearing state until Enter pressed.

### Async Validation

For commands needing external validation (file existence, LSP queries):

```zig
.file_open: struct {
    path: []const u8,
    validation_pending: bool,
},
```

**Implementation**: Completion handler triggers async validation, sets flag, returns. Separate validation callback clears flag and proceeds.

### Command Chaining

For multi-step wizards:

```zig
.replace_all: struct {
    search_text: []const u8,
    replace_text: ?[]const u8,
},
```

**Implementation**: First completion captures search text, re-activates prompt for replace text, second completion executes replacement.
