# Aesop User Guide

**Version**: 0.9.0-alpha
**Last Updated**: November 3, 2025

---

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [First Steps](#first-steps)
4. [Core Concepts](#core-concepts)
5. [Editing Workflows](#editing-workflows)
6. [Advanced Features](#advanced-features)
7. [Configuration](#configuration)
8. [Troubleshooting](#troubleshooting)
9. [Tips and Tricks](#tips-and-tricks)

---

## Introduction

Aesop is a modal text editor built in Zig that combines Vim's editing paradigm with modern editor architecture. It emphasizes:

- **Performance**: Rope-based text buffer with O(log n) operations
- **Modern features**: Tree-sitter syntax highlighting, LSP integration
- **Familiar workflow**: Vim-inspired keybindings and modal editing
- **Cross-platform**: Runs on Linux, macOS, and Windows

### Who is Aesop For?

**Developers** who want:
- Fast, responsive editing of large codebases
- LSP integration for code intelligence
- Vim keybindings without Vim's complexity

**Writers** who want:
- Distraction-free modal editing
- Powerful text manipulation
- Markdown support with live preview

**Sysadmins** who want:
- Efficient config file editing
- Regex-based search and replace
- Terminal-based workflow

---

## Installation

### Prerequisites

- **Zig 0.15.1** - Required for building from source
- **tree-sitter** - Required for syntax highlighting
- **zio** - Async I/O library (fetched automatically)
- **zigjr** - JSON-RPC for LSP (fetched automatically)

### Installing tree-sitter

**macOS (Homebrew)**:
```bash
brew install tree-sitter
```

**Linux (Debian/Ubuntu)**:
```bash
sudo apt-get install libtree-sitter-dev
```

**Linux (Arch)**:
```bash
sudo pacman -S tree-sitter
```

**From source**:
```bash
git clone https://github.com/tree-sitter/tree-sitter.git
cd tree-sitter
make
sudo make install
```

### Building Aesop

```bash
# Clone repository
git clone https://github.com/rand/aesop.git
cd aesop

# Build
zig build

# Run tests (optional)
zig build test

# Build optimized release
zig build -Doptimize=ReleaseSafe

# Binary location
./zig-out/bin/aesop
```

### Optional: Add to PATH

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/src/aesop/zig-out/bin:$PATH"

# Or create symlink
sudo ln -s ~/src/aesop/zig-out/bin/aesop /usr/local/bin/aesop
```

---

## First Steps

### Opening Aesop

```bash
# Empty buffer
aesop

# Open existing file
aesop README.md

# Demo mode (shows "Hello, World!")
aesop --demo
```

### Understanding Modes

Aesop uses **modal editing** - different modes for different tasks:

| Mode | Purpose | Enter | Exit |
|------|---------|-------|------|
| **Normal** | Navigation and commands | `Esc` | - |
| **Insert** | Text insertion | `i`, `a`, `o`, etc. | `Esc` |
| **Select** | Visual selection | `v` | `Esc` |
| **Command** | Ex commands | `:` | `Enter` or `Esc` |

**Current mode** is shown in the status line (bottom of screen).

### Your First Edit

1. **Start Aesop**: `aesop test.txt`
2. **Enter Insert mode**: Press `i`
3. **Type**: "Hello, Aesop!"
4. **Exit Insert mode**: Press `Esc`
5. **Save**: Type `:w` and press `Enter`
6. **Quit**: Type `:q` and press `Enter`

### Basic Navigation (Normal Mode)

```
h - Move left
j - Move down
k - Move up
l - Move right

w - Next word
b - Previous word
e - End of word

0 - Start of line
$ - End of line

gg - First line
G  - Last line
```

**Try it**: Open a file and navigate using `h/j/k/l` and `w/b`.

---

## Core Concepts

### The Rope Data Structure

Aesop stores text in a **rope** - a balanced tree of small chunks (512-1024 bytes each). This enables:

- **Fast edits**: Insert/delete anywhere without moving the entire file
- **Efficient undo**: Copy-on-write snapshots for every change
- **Large files**: Edit multi-megabyte files smoothly

**Impact**: You can edit at any position instantly, regardless of file size.

### Modal Editing

**Why modes?** Separate navigation from insertion to enable powerful commands.

**Normal mode**: Every key is a command
- `dd` deletes a line
- `yy` copies a line
- `3j` moves down 3 lines

**Insert mode**: Keys insert text
- Type normally
- Press `Esc` to return to Normal mode

**Select mode**: Highlight text for operations
- Press `v` to start
- Move cursor to select
- Press `d` to delete, `y` to copy

### Text Objects

**Text objects** define regions of text:

| Object | Inside (`i`) | Around (`a`) |
|--------|-------------|--------------|
| `w` - word | `iw` | `aw` (includes space) |
| `(` - parentheses | `i(` | `a(` (includes parens) |
| `"` - quotes | `i"` | `a"` (includes quotes) |
| `p` - paragraph | `ip` | `ap` (includes blank lines) |

**Examples**:
- `diw` - Delete inside word (cursor on word)
- `ci(` - Change inside parentheses
- `yi"` - Yank inside quotes
- `dap` - Delete around paragraph

### Operators and Motions

**Operators** act on text:
- `d` - delete
- `c` - change (delete and enter Insert mode)
- `y` - yank (copy)

**Motions** define where:
- `w` - to next word
- `$` - to end of line
- `j` - down one line

**Combine** operators + motions:
- `dw` - delete word
- `c$` - change to end of line
- `y3j` - yank current line + 3 below

### Registers

**Registers** are named clipboards:

| Register | Purpose |
|----------|---------|
| `"a` - `"z` | Named registers (persistent) |
| `"0` - `"9` | Numbered history (recent yanks/deletes) |
| `"+` | System clipboard |
| `"_` | Black hole (discard) |

**Usage**:
- `"ayy` - Yank line to register `a`
- `"ap` - Paste from register `a`
- `"+p` - Paste from system clipboard
- `"_dd` - Delete line (don't save)

### Undo/Redo Tree

Aesop maintains a **tree** of changes, not a linear list:

- **Undo**: `u` - Go back one change
- **Redo**: `Ctrl-r` - Go forward one change
- **Tree navigation**: Future feature

**Each change** creates a new tree node. You can undo/redo without losing work.

---

## Editing Workflows

### Basic Text Editing

**Insert text**:
```
i  - Insert before cursor
a  - Insert after cursor
I  - Insert at start of line
A  - Insert at end of line
o  - Open new line below
O  - Open new line above
```

**Delete text**:
```
x   - Delete character
dd  - Delete line
dw  - Delete word
d$  - Delete to end of line
dG  - Delete to end of file
```

**Change text** (delete + Insert mode):
```
cw  - Change word
cc  - Change line
c$  - Change to end of line
ciw - Change inside word
```

**Copy/paste**:
```
yy  - Yank line
yw  - Yank word
y$  - Yank to end of line
p   - Paste after cursor
P   - Paste before cursor
```

### Find and Replace

**Find character on line**:
```
fx  - Find next 'x'
Fx  - Find previous 'x'
tx  - Till next 'x' (cursor before)
Tx  - Till previous 'x'
;   - Repeat last find/till
,   - Reverse last find/till
```

**Search in file**:
```
/pattern  - Search forward
?pattern  - Search backward
n         - Next match
N         - Previous match
```

**Search options** (while searching):
- `/word\c` - Case-insensitive
- `/\<word\>` - Whole word only

### Working with Multiple Files

**Buffer commands**:
```
:e filename  - Edit file
:w           - Write (save)
:q           - Quit
:wq          - Write and quit
:q!          - Quit without saving
:b           - Show buffer list
:bn          - Next buffer
:bp          - Previous buffer
```

**File finder** (fuzzy search):
```
Space + f  - Open file finder
Type to search
Enter      - Open selected file
Esc        - Cancel
```

### Window Management

**Split windows**:
```
:split    - Horizontal split
:vsplit   - Vertical split
Ctrl-w h  - Move to left window
Ctrl-w j  - Move to window below
Ctrl-w k  - Move to window above
Ctrl-w l  - Move to right window
Ctrl-w =  - Equalize window sizes
```

### Marks and Macros

**Marks** (bookmarks):
```
ma   - Set mark 'a' at cursor
`a   - Jump to mark 'a'
`A   - Jump to global mark 'A' (cross-file)
```

**Macros** (record and replay):
```
qa        - Record macro to register 'a'
(commands)
q         - Stop recording
@a        - Play macro from register 'a'
@@        - Replay last macro
```

**Example macro**: Add semicolon to end of 10 lines
```
qa   - Start recording to 'a'
A;   - Append semicolon
Esc  - Exit Insert mode
j    - Move down
q    - Stop recording
9@a  - Replay 9 more times
```

---

## Advanced Features

### Tree-sitter Syntax Highlighting

**Supported languages**: Zig, Rust, Go, Python, C

**How it works**:
- Incremental parsing (only re-parse changed regions)
- Query-based highlighting (customizable)
- Error recovery (highlights partial/broken code)

**Performance**: Parsing happens on text change, highlighting is near-instant.

**Note**: Requires language grammars installed (see `docs/BUILDING_WITH_TREE_SITTER.md`).

### LSP Integration

**Language Server Protocol** provides:
- **Diagnostics**: Errors and warnings with gutter indicators
- **Completion**: Trigger with `Ctrl-Space` in Insert mode
- **Hover**: Type info with `K` in Normal mode
- **Go to definition**: `gd` in Normal mode

**Setup**:
1. Install language server (e.g., `zls` for Zig, `rust-analyzer` for Rust)
2. Ensure server is in `PATH`
3. Open file - LSP starts automatically

**LSP commands**:
```
K           - Hover documentation
gd          - Go to definition
Space + r   - Rename symbol
Space + a   - Code actions
```

**Diagnostics**:
- Errors shown with `E` in gutter
- Warnings shown with `W` in gutter
- Hover over diagnostic line for details

### Multi-Cursor Editing

**Create cursors**:
```
Ctrl-d  - Add cursor at next match of word under cursor
Ctrl-u  - Undo last cursor
```

**Usage**:
1. Position cursor on word
2. Press `Ctrl-d` to add cursor at next occurrence
3. Repeat to add more cursors
4. Edit as normal - all cursors move together

**Example**: Rename variable `foo` to `bar`
```
/foo    - Search for 'foo'
Ctrl-d  - Add cursor at next 'foo'
Ctrl-d  - Add more cursors
ciw     - Change inside word (all cursors)
bar     - Type new name
Esc     - Exit Insert mode
```

### Command Palette

**Access**: `Space + P`

**Available commands**:
- `config_show` - Show current settings
- `config_write` - Save configuration
- `lsp_hover` - LSP hover info
- `lsp_goto_def` - Go to definition
- `lsp_rename` - Rename symbol
- `format` - Format document
- `show_marks` - List all marks

**Usage**:
1. Press `Space + P`
2. Type command name (fuzzy matching)
3. Press `Enter` to execute
4. Press `Esc` to cancel

### Incremental Search

**Interactive search-as-you-type**:

```
/        - Start search
(type)   - See matches highlighted live
Enter    - Jump to first match
Esc      - Cancel search
```

**Features**:
- Live match highlighting
- Match count display
- Regex support
- History (up/down arrows)

---

## Configuration

Aesop uses a simple `key=value` configuration file.

### Config File Location

1. `$XDG_CONFIG_HOME/aesop/config.conf` (if set)
2. `~/.config/aesop/config.conf` (default)
3. `./aesop.conf` (local override)

### Example Configuration

```conf
# Editor behavior
tab_width=4
expand_tabs=true
line_numbers=true
relative_line_numbers=false

# Visual
syntax_highlighting=true
highlight_current_line=true

# Search
search_case_sensitive=false
search_wrap_around=true

# Auto-pairing
auto_pair_brackets=true
```

### Common Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `tab_width` | 1-16 | `4` | Tab width in spaces |
| `expand_tabs` | bool | `true` | Use spaces for Tab key |
| `line_numbers` | bool | `true` | Show line numbers |
| `relative_line_numbers` | bool | `false` | Show relative numbers |
| `syntax_highlighting` | bool | `true` | Enable highlighting |
| `auto_pair_brackets` | bool | `true` | Auto-close brackets |
| `search_case_sensitive` | bool | `false` | Case-sensitive search |
| `max_undo_history` | int | `1000` | Undo stack depth |

### Viewing/Saving Config

**View current settings**:
```
Space + P
config_show
```

**Save current settings**:
```
Space + P
config_write
```

See **[Configuration System](features/configuration.md)** for complete details.

---

## Troubleshooting

### Editor Won't Start

**Check Zig version**:
```bash
zig version
# Should show: 0.15.1
```

**Rebuild**:
```bash
cd ~/src/aesop
zig build clean
zig build
```

**Check tree-sitter**:
```bash
# macOS
brew list tree-sitter

# Linux
ldconfig -p | grep tree-sitter
```

### Syntax Highlighting Not Working

**Verify language support**:
- Supported: Zig, Rust, Go, Python, C
- File extension must match (`.zig`, `.rs`, `.go`, `.py`, `.c`)

**Check grammars installed**:
```bash
# See docs/BUILDING_WITH_TREE_SITTER.md for installation
ls /opt/homebrew/lib/libtree-sitter-*.dylib  # macOS
ls /usr/local/lib/libtree-sitter-*.so         # Linux
```

**Enable in config**:
```conf
syntax_highlighting=true
```

### LSP Not Starting

**Check server installed**:
```bash
which zls           # Zig
which rust-analyzer # Rust
which gopls         # Go
which pyright       # Python
```

**Check stderr log**:
```bash
# LSP stderr is logged to terminal
# Look for connection errors
```

**Verify file type**:
- LSP only starts for supported languages
- File extension must match

### Slow Performance

**Large files**:
```conf
syntax_highlighting=false
max_undo_history=100
highlight_current_line=false
```

**Disable LSP** (if language server is slow):
```
# Kill language server
killall zls
```

**Reduce undo history**:
```conf
max_undo_history=100
```

### Config Not Loading

**Check file exists**:
```bash
ls -la ~/.config/aesop/config.conf
```

**Check format**:
```conf
# Correct
tab_width=4

# Incorrect (no spaces around =)
tab_width = 4
```

**View loaded config**:
```
Space + P
config_show
```

---

## Tips and Tricks

### Efficient Navigation

**Jump to line**:
```
:42     - Jump to line 42
42G     - Same (Normal mode)
gg      - First line
G       - Last line
```

**Jump within line**:
```
0   - Start of line
^   - First non-whitespace
$   - End of line
g_  - Last non-whitespace
```

**Jump by paragraph**:
```
{   - Previous paragraph
}   - Next paragraph
```

### Powerful Deletions

**Delete patterns**:
```
dt;     - Delete till semicolon
df)     - Delete including closing paren
d/foo   - Delete until "foo" (searches)
dG      - Delete to end of file
d1G     - Delete to start of file
```

### Repeat Last Change

**The dot command** (`.`) repeats the last change:

```
dd   - Delete line
.    - Delete another line
.    - Delete another line
```

**Useful pattern**: Make one complex change, then repeat with `.`

### Search and Replace Pattern

**Quick workflow**:
```
/old      - Search for "old"
cwNew     - Change word to "New"
Esc       - Exit Insert mode
n         - Next match
.         - Repeat change
n.        - Next match and change
```

### Copy/Paste System Clipboard

**Yank to system clipboard**:
```
"+yy    - Yank line to clipboard
"+y$    - Yank to end of line
"+yiw   - Yank word
```

**Paste from system clipboard**:
```
"+p     - Paste after cursor
"+P     - Paste before cursor
```

### File Finder Workflow

```
Space + f    - Open file finder
src/ed       - Type partial path
Enter        - Open matched file
```

**Fuzzy matching** means you don't need exact names.

### Efficient Window Splits

**Quick workflow**:
```
:vsplit header.zig    - Split vertically, open header
:split impl.zig       - Split horizontally, open impl
Ctrl-w =              - Equalize sizes
Ctrl-w h/j/k/l        - Navigate splits
```

### Macro for Repetitive Tasks

**Example**: Convert list to assignments
```
Before:
foo
bar
baz

Desired:
let foo = null;
let bar = null;
let baz = null;

Macro:
qa              - Record to 'a'
Ilet<Space>     - Insert "let "
Esc             - Exit Insert
A = null;       - Append " = null;"
Esc             - Exit Insert
j               - Move down
q               - Stop recording
2@a             - Replay twice
```

### Mark for Quick Navigation

**Set marks at key locations**:
```
ma   - Mark current function as 'a'
mb   - Mark test section as 'b'
mc   - Mark main as 'c'

`a   - Jump to function
`b   - Jump to tests
`c   - Jump to main
```

**Global marks** (uppercase) work across files:
```
mA   - Mark this file location
:e other.zig
`A   - Jump back to marked location in first file
```

### Combine Text Objects and Operators

**Powerful combinations**:
```
ci"     - Change inside quotes
da(     - Delete around parentheses
yi{     - Yank inside braces
cap     - Change around paragraph
di<     - Delete inside angle brackets
```

**Works with any pairing**: `()`, `[]`, `{}`, `<>`, `""`, `''`

### Search Shortcuts

**Search for word under cursor**:
```
*   - Search forward for word under cursor
#   - Search backward for word under cursor
n   - Next match
N   - Previous match
```

**Case-insensitive search**:
```
/pattern\c   - Case-insensitive
/pattern\C   - Case-sensitive (force)
```

---

## Next Steps

### Learning More

- **[Quick Start](QUICK_START.md)** - More hands-on examples
- **[Interactive Commands](features/interactive-commands.md)** - Detailed command reference
- **[Configuration](features/configuration.md)** - Complete settings guide
- **[API Documentation](API.md)** - Extend Aesop with plugins

### Getting Help

- **GitHub Issues**: https://github.com/rand/aesop/issues
- **Documentation**: `docs/` directory
- **Source Code**: Read the code! It's well-commented

### Contributing

Contributions welcome! See the source code for contribution guidelines.

---

**Happy editing!**
