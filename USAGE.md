# Aesop Usage Guide

Aesop is a high-performance modal text editor that requires a terminal (TTY) to run.

## Installation

The editor is installed to `~/.local/bin/aesop` with a wrapper script that sets the required library path.

Ensure `~/.local/bin` is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add this to your `~/.zshrc` or `~/.bashrc` to make it permanent.

## Running Aesop

### Interactive Terminal (Required)

Aesop **must** be run in an interactive terminal session:

```bash
# Open a file
aesop myfile.txt

# Run the welcome demo
aesop --demo

# Start with empty buffer
aesop
```

### What Doesn't Work

Aesop will **not** work in these contexts:
- ❌ Piped input: `echo "text" | aesop`
- ❌ Output redirection: `aesop file.txt > output`
- ❌ Background processes without TTY: `aesop file.txt &`
- ❌ Automation contexts (Claude Code, CI/CD, scripts)

If you try to run Aesop without a TTY, you'll see:
```
error: Aesop requires a terminal (TTY) to run.
Please run Aesop directly in a terminal, not through a pipe or redirect.
```

## Basic Usage

Once running in a terminal:

### Navigation
- Arrow keys: Move cursor
- Page Up/Down: Scroll by page
- Home/End: Start/end of line
- Ctrl+Home/End: Start/end of file

### Editing
- Type to insert text
- Backspace/Delete: Remove characters
- Enter: New line
- Tab: Insert tab

### Commands
- `:q` - Quit
- `:w` - Save
- `:wq` - Save and quit

### File Tree
- `Space e` - Toggle file tree sidebar
- When file tree is visible:
  - Arrow keys (`↑`/`↓`) or `j`/`k` - Navigate up/down
  - `Enter` - Open file or toggle directory expand/collapse
  - `Space e` - Close file tree

The file tree displays the current working directory structure in a sidebar. Files are automatically opened in the editor when selected, and the tree closes to give you full editing space.

### Features
- **File Tree Browser**: Navigate project structure with `Space e`
- **Syntax Highlighting**: Zig, Rust, Go, Python, C
- **LSP Integration**: Code completion, hover, go-to-definition
- **Undo/Redo**: With branching support (vim-style undo tree)
- **Marks**: Quick navigation to saved positions
- **Multiple Buffers**: Switch between open files

## System Requirements

- **Operating System**: macOS, Linux, or Unix-like system
- **Terminal**: Any VT100/xterm compatible terminal
- **Dependencies**: tree-sitter libraries (installed to `~/lib/`)

## Libraries

Aesop uses these tree-sitter grammar libraries (installed to `~/lib/`):
- `libtree-sitter-zig.dylib`
- `libtree-sitter-rust.dylib`
- `libtree-sitter-go.dylib`
- `libtree-sitter-python.dylib`
- `libtree-sitter-c.dylib`

The wrapper script at `~/.local/bin/aesop` automatically sets `DYLD_LIBRARY_PATH` to find these libraries.

## Troubleshooting

### "Library not loaded" errors
If you see library loading errors, ensure the wrapper script is being used:
```bash
which aesop  # Should show ~/.local/bin/aesop (the wrapper)
```

### "Not a terminal" error
This means you're trying to run Aesop in a non-interactive context. Open a real terminal window and run Aesop there.

### Key bindings don't work
Ensure your terminal emulator is properly configured for VT100/xterm escape sequences.

## Version

Current release: **v0.9.0**

See [CHANGELOG.md](CHANGELOG.md) for release notes and version history.
