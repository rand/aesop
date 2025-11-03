# Quick Start Guide

Fast-track examples to get productive with Aesop immediately.

---

## 5-Minute Intro

### Installation

```bash
# Install tree-sitter
brew install tree-sitter  # macOS
# OR
sudo apt-get install libtree-sitter-dev  # Linux

# Build Aesop
git clone https://github.com/rand/aesop.git
cd aesop
zig build

# Run
./zig-out/bin/aesop
```

### First Edit

```bash
# Open new file
./zig-out/bin/aesop hello.txt

# Press 'i' to enter Insert mode
# Type: "Hello, Aesop!"
# Press Esc to exit Insert mode
# Type: :wq and press Enter
```

**You've created and saved your first file!**

---

## Common Tasks

### Task 1: Edit Existing File

```bash
# Open file
aesop README.md

# Navigate with h/j/k/l (left/down/up/right)
# Press 'w' to jump forward by word
# Press '0' to jump to start of line
# Press '$' to jump to end of line
```

### Task 2: Delete and Change Text

```bash
# Delete line: dd
# Delete word: dw
# Delete character: x

# Change line: cc (deletes and enters Insert mode)
# Change word: cw
# Change to end of line: c$
```

### Task 3: Copy and Paste

```bash
# Copy line: yy
# Copy word: yw
# Paste after cursor: p
# Paste before cursor: P

# Example: Duplicate line
yy    # Copy current line
p     # Paste below
```

### Task 4: Search and Replace

```bash
# Search: /pattern
# Press 'n' for next match
# Press 'N' for previous match

# Example: Find all instances of "foo"
/foo
n     # Next match
n     # Next match
```

**Manual replace**:
```bash
/old       # Search for "old"
cwNew      # Change word to "New"
Esc        # Exit Insert mode
n          # Next match
.          # Repeat change (the dot command!)
```

### Task 5: Work with Multiple Files

```bash
# Open file finder
Space + f

# Type partial path: src/main
# Press Enter to open

# Switch buffers
:bn       # Next buffer
:bp       # Previous buffer
:b        # Show buffer list
```

### Task 6: Split Windows

```bash
# Vertical split
:vsplit other_file.zig

# Horizontal split
:split header.zig

# Navigate between windows
Ctrl-w h   # Left
Ctrl-w j   # Down
Ctrl-w k   # Up
Ctrl-w l   # Right
```

---

## Real-World Workflows

### Workflow 1: Developer - Write a Function

**Scenario**: Write a Zig function with LSP assistance

```bash
# Open file
aesop src/utils.zig

# Insert new function
o                           # Open new line
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
Esc

# Format with LSP (if zls installed)
Space + P
format

# Save
:w
```

**With LSP features**:
- `K` on a symbol for hover documentation
- `gd` to go to definition
- `Ctrl-Space` for completion (in Insert mode)

### Workflow 2: Writer - Edit Prose

**Scenario**: Write and edit a blog post

```bash
# Create new file
aesop blog_post.md

# Enter Insert mode and write
i
# Introduction

Today I want to talk about modal editing...
Esc

# Navigate between paragraphs
}     # Next paragraph
{     # Previous paragraph

# Delete paragraph
dap   # Delete around paragraph

# Search for word
/editing
n     # Next occurrence
```

### Workflow 3: Sysadmin - Edit Config

**Scenario**: Update nginx configuration

```bash
# Open config
aesop /etc/nginx/nginx.conf

# Find server block
/server {

# Change port
/listen
cw8080   # Change word to "8080"
Esc

# Comment out line
I#       # Insert '#' at start of line
Esc

# Uncomment line
0x       # Jump to start, delete character

# Save
:w
```

### Workflow 4: Refactor Code

**Scenario**: Rename variable `count` to `total`

```bash
# Open file
aesop src/counter.zig

# Search for variable
/count

# Add cursors at each occurrence
Ctrl-d    # Add cursor at next "count"
Ctrl-d    # Add cursor at next "count"
Ctrl-d    # Keep adding...

# Change all at once
ciw       # Change inside word (all cursors)
total     # Type new name
Esc       # Exit Insert mode

# All instances changed!
```

**Alternative with LSP**:
```bash
# Position cursor on "count"
Space + P
lsp_rename

# (Future: will prompt for new name)
```

### Workflow 5: Code Review Workflow

**Scenario**: Review code changes across multiple files

```bash
# Open first file
aesop src/main.zig

# Set mark at interesting location
ma

# Open related file
:e src/utils.zig

# Set mark at another location
mb

# Jump between marks
`a    # Jump to main.zig location
`b    # Jump to utils.zig location

# Add comments as you review
o
// TODO: This should validate input
Esc
```

---

## Example Sessions

### Session 1: Quick Edit

```
$ aesop config.conf
# Press 'i' - Enter Insert mode
# Add line: port=8080
# Press Esc
# Type :wq - Save and quit
```

**Time**: 10 seconds

### Session 2: Search and Edit

```
$ aesop server.go
# Type /handleRequest - Search for function
# Press 'n' - Go to next match
# Press 'dd' - Delete line
# Press 'o' - Open new line
# Type new code
# Press Esc
# Type :w - Save
```

**Time**: 30 seconds

### Session 3: Multi-File Edit

```
$ aesop src/main.zig
# Press Space+f - Open file finder
# Type utils - Find utils.zig
# Press Enter - Open file
# Edit...
# Press :bn - Next buffer (back to main.zig)
# Edit...
# Press :w - Save all changes
```

**Time**: 1 minute

---

## Power User Shortcuts

### Navigation

```
gg        - First line
G         - Last line
42G       - Line 42
%         - Matching bracket
{         - Previous paragraph
}         - Next paragraph
*         - Search word under cursor
#         - Search backward for word under cursor
```

### Editing

```
dd        - Delete line
yy        - Copy line
p         - Paste
.         - Repeat last change
u         - Undo
Ctrl-r    - Redo
J         - Join lines
>>        - Indent line
<<        - Un-indent line
```

### Text Objects (operator + text object)

```
diw       - Delete inside word
ciw       - Change inside word
yiw       - Yank inside word
di"       - Delete inside quotes
ci(       - Change inside parentheses
da{       - Delete around braces
yap       - Yank around paragraph
```

### Macros (record once, replay many)

```
qa        - Record macro to register 'a'
(commands)
q         - Stop recording
@a        - Play macro 'a'
10@a      - Play macro 10 times
@@        - Replay last macro
```

### Registers

```
"ayy      - Yank line to register 'a'
"ap       - Paste from register 'a'
"+yy      - Yank to system clipboard
"+p       - Paste from system clipboard
"_dd      - Delete without saving to register
```

---

## Configuration Quick Start

### Create Config File

```bash
mkdir -p ~/.config/aesop
cat > ~/.config/aesop/config.conf <<'EOF'
# My Aesop Configuration
tab_width=4
expand_tabs=true
line_numbers=true
syntax_highlighting=true
auto_pair_brackets=true
search_case_sensitive=false
EOF
```

### Minimal Config (Programming)

```conf
tab_width=4
expand_tabs=true
line_numbers=true
syntax_highlighting=true
```

### Minimal Config (Writing)

```conf
tab_width=2
line_numbers=false
syntax_highlighting=false
wrap_lines=true
```

### View/Save Config from Editor

```
# View settings
Space + P
config_show

# Save current settings
Space + P
config_write
```

---

## LSP Quick Start

### Install Language Servers

```bash
# Zig
# zls is typically bundled with Zig installation
which zls

# Rust
rustup component add rust-analyzer
which rust-analyzer

# Go
go install golang.org/x/tools/gopls@latest
which gopls

# Python
pip install pyright
which pyright
```

### Using LSP Features

**Hover documentation**:
```
# Position cursor on symbol
# Press 'K'
# Documentation appears
```

**Go to definition**:
```
# Position cursor on symbol
# Press 'gd'
# Jump to definition
```

**Code completion**:
```
# Enter Insert mode
# Start typing
# Press Ctrl-Space
# Select completion with arrow keys + Enter
```

**View diagnostics**:
- Errors show `E` in gutter
- Warnings show `W` in gutter
- Hover over line for details

---

## Troubleshooting Quick Fixes

### "Command not found: aesop"

```bash
# Add to PATH
export PATH="$HOME/src/aesop/zig-out/bin:$PATH"

# Or create symlink
sudo ln -s ~/src/aesop/zig-out/bin/aesop /usr/local/bin/aesop
```

### "Syntax highlighting not working"

```bash
# Check tree-sitter installed
brew list tree-sitter  # macOS
ldconfig -p | grep tree-sitter  # Linux

# Enable in config
echo "syntax_highlighting=true" >> ~/.config/aesop/config.conf
```

### "LSP not starting"

```bash
# Check language server installed
which zls           # Zig
which rust-analyzer # Rust
which gopls         # Go
which pyright       # Python

# Check file extension matches (.zig, .rs, .go, .py)
```

### "Editor is slow"

```bash
# Disable features for large files
cat >> ~/.config/aesop/config.conf <<'EOF'
syntax_highlighting=false
max_undo_history=100
EOF
```

---

## Next Steps

- **[User Guide](USER_GUIDE.md)** - Comprehensive guide
- **[Configuration](features/configuration.md)** - All settings
- **[Interactive Commands](features/interactive-commands.md)** - Detailed command reference
- **[API Documentation](API.md)** - Extend with plugins

---

**Quick reference card**: Keep this page bookmarked for fast lookup!
