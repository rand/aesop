# Interactive Commands

Commands that require additional user input use the prompt system to request parameters without blocking the editor.

## How It Works

Interactive commands work in two steps:

1. **Initiate**: Press the command key (e.g., `f` for find)
2. **Complete**: The prompt appears, requesting input (e.g., character to find)

Between these steps, the editor remains responsive. You can cancel any interactive command with `Escape`.

## Find and Till Character Motions

### Find Character Forward (f)

Moves cursor to the next occurrence of a character.

**Usage**:
1. Press `f`
2. Prompt shows: "Find char:"
3. Type target character (e.g., `x`)
4. Cursor jumps to next `x` in current line

**Example**:
```
Before:  "The quick brown fox"
         ^cursor

After f→o:  "The quick brown fox"
                          ^cursor
```

**Notes**:
- Only searches current line (vim behavior)
- If character not found, shows "Character not found" message
- In visual mode, extends selection to target character

### Find Character Backward (F)

Same as `f`, but searches backward from cursor.

**Usage**:
1. Press `F`
2. Type target character
3. Cursor jumps to previous occurrence

### Till Character Forward (t)

Moves cursor to one position *before* the target character.

**Usage**:
1. Press `t`
2. Type target character
3. Cursor stops one position before character

**Example**:
```
Before:  "The quick brown fox"
         ^cursor

After t→o:  "The quick brown fox"
                         ^cursor (before 'o')
```

**Use Case**:
Useful for commands like `dt)` (delete till closing paren) where you want to preserve the delimiter.

### Till Character Backward (T)

Same as `t`, but searches backward.

### Repeating Find/Till (;)

After using any find/till command, press `;` to repeat it without prompting again.

**Example**:
```
fx     # Find 'x' (prompts for character)
;      # Find next 'x' (no prompt)
;      # Find next 'x' (no prompt)
```

The repeat command uses the same direction and mode (find vs till) as the original command.

### Reversing Find/Till (,)

Press `,` to repeat the last find/till in the opposite direction.

**Example**:
```
fx     # Find 'x' forward
,      # Find 'x' backward
,      # Find 'x' backward again
```

## Marks

Marks bookmark cursor positions for quick navigation.

### Set Mark (m)

Records current cursor position in a register.

**Usage**:
1. Press `m`
2. Prompt shows: "Mark:"
3. Type register name (a-z or A-Z)

**Example**:
```
ma     # Set mark 'a' at current position
```

**Notes**:
- Lowercase marks (a-z): File-local
- Uppercase marks (A-Z): Global across files
- Marks persist across buffer switches
- Invalid register names (numbers, symbols) show error message

### Jump to Mark (`)

Returns to a saved mark position.

**Usage**:
1. Press `` ` `` (backtick)
2. Prompt shows: "Go to mark:"
3. Type register name

**Example**:
```
ma        # Set mark 'a'
[...navigate elsewhere...]
`a        # Jump back to mark 'a'
```

**Cross-File Navigation**:
If a mark is in a different buffer, jumping to it automatically switches buffers:
```
# In file1.txt
mA        # Set global mark 'A'

# Switch to file2.txt
`A        # Jumps to file1.txt at mark 'A' position
```

**Notes**:
- Unset marks show error: "Mark 'x' not set"
- Cursor moves to exact line and column of mark

### List Marks (:marks)

Shows all currently set marks.

**Output**: Count of active marks (full display in future versions)

## Macros

Macros record command sequences for playback.

### Record Macro (q)

Starts recording commands to a register.

**Usage**:
1. Press `q`
2. Prompt shows: "Record macro to register:"
3. Type register name (a-z)
4. Execute commands to record
5. Press `q` again to stop recording

**Example**:
```
qa        # Start recording to register 'a'
dw        # Delete word
i         # Enter insert mode
TODO:     # Type text
<Esc>     # Return to normal mode
q         # Stop recording
```

**Notes**:
- Only lowercase registers (a-z) are supported
- Recording to existing register overwrites it
- Macro recording/playback commands (`q`, `@`) are not recorded in macros (prevents recursion issues)
- Macros persist in registers until overwritten

### Play Macro (@)

Executes a recorded macro.

**Usage**:
1. Press `@`
2. Prompt shows: "Play macro from register:"
3. Type register name

**Example**:
```
qa        # Record macro to 'a'
[...commands...]
q         # Stop recording

@a        # Play macro from 'a'
@a        # Play it again
```

**Playback Behavior**:
- Commands execute sequentially
- If a command fails, error is shown but playback continues
- Empty registers show: "Register 'x' is empty"
- Unset registers show same error

**Common Pattern - Repeat on Multiple Lines**:
```
qa        # Start recording
dw        # Delete first word
j         # Move down
q         # Stop recording

9@a       # Repeat on next 9 lines
```

### Stop Recording (q)

Stops an active macro recording session.

**Usage**: Press `q` while recording

**Feedback**: Message shows "Macro saved" on success

## Replace Character (r)

Replaces character at cursor with a new character.

**Usage**:
1. Press `r`
2. Prompt shows: "Replace char:"
3. Type replacement character
4. Character at cursor is replaced

**Example**:
```
Before:  "The quick brown fox"
         ^cursor on 'T'

After r→t:  "the quick brown fox"
            ^cursor still on 't'
```

**Notes**:
- Cursor position doesn't change (vim behavior)
- Works on single character only (use visual mode + `c` for multiple)
- In visual mode, would replace all selected characters (future enhancement)

## Cancelling Interactive Commands

**Any** interactive command can be cancelled before completion:

1. Press command key (e.g., `f`, `m`, `q`, `@`)
2. Prompt appears requesting input
3. Press `Escape`
4. Command cancelled, prompt hidden, no action taken

**Example**:
```
f         # Start find char
<Esc>     # Cancel - no motion occurs
```

This is useful when you change your mind or pressed the wrong command key.

## Integration with Visual Mode

Interactive commands work in visual mode with context-appropriate behavior:

### Find/Till in Visual Mode

Extends selection instead of moving cursor alone:

```
v         # Enter visual mode
fx        # Find 'x' - selection extends to 'x'
```

**Use Case**: Select text up to a delimiter:
```
vt)       # Select till closing paren (excludes paren)
vf)       # Select till closing paren (includes paren)
```

### Marks in Visual Mode

Setting marks in visual mode records the cursor position:
```
v3w       # Select 3 words
ma        # Mark 'a' at cursor (selection head)
```

Jumping to marks exits visual mode and moves cursor.

## Common Patterns

### Navigate to Definition and Back

```
ma        # Mark current position as 'a'
gd        # Jump to definition (hypothetical command)
`a        # Return to previous position
```

### Delete to Character

```
df,       # Delete forward to comma (inclusive)
dt,       # Delete till comma (exclusive)
```

### Macro for Repetitive Edits

```
qa        # Start recording
^         # Move to line start
cw        # Change word
NEW       # Type replacement
<Esc>     # Exit insert mode
j         # Move to next line
q         # Stop recording

10@a      # Apply to next 10 lines
```

### Cross-File Bookmark

```
# In file1.txt
mA        # Set global mark 'A'

# Navigate to file2.txt, file3.txt, etc.

`A        # Return to file1.txt at mark 'A'
```

## Error Handling

Interactive commands validate input and show clear error messages:

| Error | Cause | Solution |
|-------|-------|----------|
| "Character not found" | find/till can't locate character | Try backward search or different character |
| "Invalid mark name (use a-z, A-Z)" | Used number or symbol as mark | Use alphabetic register |
| "Mark 'x' not set" | Jumped to unset mark | Set mark first with `mx` |
| "Invalid register (use a-z)" | Used invalid register for macro | Use lowercase letter |
| "Register 'x' is empty" | Played macro from empty register | Record macro first with `qx` |
| "Not recording" | Stopped recording when not recording | Start recording first with `qx` |
| "Already recording a macro" | Started recording while recording | Stop current recording with `q` first |

## Differences from Vim

### Simplifications

- Marks don't track line vs exact position (always exact)
- No mark change list (no `g;`/`g,` for navigating mark history)
- Macro playback doesn't support count prefix directly (use `@@` to repeat last macro)

### Enhancements

- All interactive commands can be cancelled with Escape
- Clear, consistent prompt messages for all inputs
- Graceful error handling (no crashes on invalid input)
- Macro errors don't halt playback (continues with remaining commands)

## Implementation Notes

These commands use the **prompt system** for input, which:
- Doesn't block the editor (event loop stays responsive)
- Allows cancellation at any time
- Shows clear prompts for expected input
- Validates input before executing actions

This architecture ensures consistent behavior across all interactive commands while maintaining editor responsiveness.
