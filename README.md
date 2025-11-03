# Aesop

A modern modal text editor written in Zig with vim-like keybindings and a focus on performance.

[![CI](https://github.com/rand/aesop/actions/workflows/ci.yml/badge.svg)](https://github.com/rand/aesop/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/Zig-0.15.1-orange.svg)](https://ziglang.org)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-blue.svg)](https://github.com/rand/aesop)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Overview

Aesop is a terminal-based text editor that combines the modal editing paradigm of Vim with modern editor architecture. Built from scratch in Zig, it prioritizes performance through efficient data structures and aims to provide a familiar yet refined editing experience.

**Status**: Active development. Core editing features are functional, but this is not yet production-ready.

## Features

### Core Architecture

- **Rope data structure** - Efficient text manipulation inspired by xi-editor and Zed, with O(log n) insert/delete and copy-on-write semantics for undo/redo
- **UTF-8 native** - Full Unicode support throughout the editor
- **Async I/O** - Built on zio for responsive file operations
- **Cross-platform** - Runs on Linux, macOS, and Windows

### Vim-Inspired Editing

- **Modal editing** - Normal, Insert, Select, and Command modes
- **Motion commands** - `h/j/k/l`, `w/b/e`, `0/$`, `gg/G`, `{/}`
- **Text objects** - `iw/aw` (word), `ip/ap` (paragraph), `i(/a(` and other pairs
- **Find/till motions** - `f/F/t/T{char}` with `;` and `,` repeat
- **Marks** - `m{a-z}` to set, `` `{mark} `` to jump, with cross-file support for uppercase marks
- **Registers** - Named clipboards (a-z), numbered history (0-9), system clipboard (+), black hole (_)
- **Macros** - `q{register}` to record, `@{register}` to play, with persistent storage
- **Search** - `/` with regex, case-sensitive/insensitive, whole-word matching, and search history
- **Undo/redo** - Tree-based history with `u` and `Ctrl-r`
- **Repeat** - `.` repeats last change

### Modern Features

- **Tree-sitter syntax highlighting** - Fast, accurate syntax highlighting using tree-sitter with support for Zig, Rust, Go, Python, and C
- **LSP integration** - Language Server Protocol support for code intelligence
  - Diagnostics with gutter indicators
  - Code completion
  - Hover documentation
  - Go to definition
  - Background stderr logging for debugging
- **Prompt system** - Non-blocking interactive commands with escape cancellation
- **Incremental search** - Search-as-you-type with live match highlighting
- **Auto-pairing** - Automatic bracket/quote pairing with smart deletion
- **File finder** - Fuzzy file search across project
- **Multiple buffers** - Buffer switching with `:b` and buffer list
- **Multiple cursors** - Multi-cursor editing support
- **Window management** - Split windows horizontally and vertically with dynamic resizing
- **Status line** - Shows mode, file, position, and buffer state

## Installation

### Prerequisites

- [Zig 0.15.1](https://ziglang.org/download/) (required)
- [tree-sitter](https://tree-sitter.github.io/) (required for syntax highlighting)

### Building from Source

```bash
# Clone the repository
git clone https://github.com/rand/aesop.git
cd aesop

# Build the editor
zig build

# Run tests
zig build test

# Build optimized release
zig build -Doptimize=ReleaseSafe
```

The compiled binary will be in `zig-out/bin/aesop`.

### Tree-sitter Setup

Aesop uses tree-sitter for fast, accurate syntax highlighting. The tree-sitter core library is required:

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

For detailed setup including language-specific grammar installation, see [docs/BUILDING_WITH_TREE_SITTER.md](docs/BUILDING_WITH_TREE_SITTER.md).

### Running

```bash
# Open empty buffer
./zig-out/bin/aesop

# Open a file
./zig-out/bin/aesop path/to/file.txt

# Run demo mode (shows "Hello, World!")
./zig-out/bin/aesop --demo
```

## Quick Start

Aesop uses modal editing similar to Vim:

### Basic Navigation

```
h/j/k/l    - Move cursor left/down/up/right
w/b        - Jump forward/backward by word
0/$        - Jump to start/end of line
gg/G       - Jump to first/last line
{number}G  - Jump to line number
```

### Modes

```
i          - Enter Insert mode (before cursor)
a          - Enter Insert mode (after cursor)
v          - Enter Select (visual) mode
Esc        - Return to Normal mode
```

### Editing

```
x          - Delete character
dd         - Delete line
yy         - Yank (copy) line
p          - Paste after cursor
u          - Undo
Ctrl-r     - Redo
.          - Repeat last change
```

### Text Objects

```
diw        - Delete inside word
ci(        - Change inside parentheses
ya"        - Yank around double quotes
dap        - Delete around paragraph
```

### Find and Till

```
fx         - Find next 'x' on line
Fx         - Find previous 'x' on line
tx         - Till next 'x' (cursor before 'x')
Tx         - Till previous 'x'
;          - Repeat last find/till
,          - Reverse last find/till
```

### Marks and Macros

```
ma         - Set mark 'a' at cursor
`a         - Jump to mark 'a'
qa         - Start recording macro to register 'a'
q          - Stop recording
@a         - Play macro from register 'a'
```

### Search

```
/pattern   - Search forward
?pattern   - Search backward
n          - Next match
N          - Previous match
```

## Configuration

Aesop supports comprehensive configuration through a simple key=value config file:

### Config File Location

1. `$XDG_CONFIG_HOME/aesop/config.conf` (if XDG_CONFIG_HOME is set)
2. `~/.config/aesop/config.conf` (default)
3. `./aesop.conf` (current directory)

### Example Configuration

```conf
# Editor behavior
tab_width=4
expand_tabs=true
line_numbers=true
relative_line_numbers=false

# Visual settings
syntax_highlighting=true
highlight_current_line=true

# Search defaults
search_case_sensitive=false
search_wrap_around=true

# Auto-pairing
auto_pair_brackets=true
```

### Config Commands

- **config_show** (via Space+P command palette) - Display current settings
- **config_write** (via Space+P command palette) - Save configuration to `~/.config/aesop/config.conf`

See **[Configuration System](docs/features/configuration.md)** documentation for complete details on all available settings.

## Documentation

Detailed documentation is available in the `docs/` directory:

- **[Configuration System](docs/features/configuration.md)** - Configuration file format, settings, and usage
- **[Prompt System Architecture](docs/architecture/prompt-system.md)** - Design and implementation of non-blocking interactive commands
- **[Interactive Commands](docs/features/interactive-commands.md)** - User guide for prompted commands (find/till, marks, macros)

## Development

### Project Structure

```
src/
├── buffer/          - Rope data structure for text storage
├── editor/          - Core editor logic
│   ├── command.zig  - Command registry and implementations
│   ├── cursor.zig   - Cursor and selection management
│   ├── editor.zig   - Main editor state coordinator
│   ├── highlight.zig - Syntax highlighting tokenizer
│   ├── keymap.zig   - Key binding system
│   ├── macros.zig   - Macro recording/playback
│   ├── marks.zig    - Mark/bookmark system
│   ├── motions.zig  - Cursor motion implementations
│   ├── prompt.zig   - Interactive prompt system
│   ├── registers.zig - Register management
│   ├── search.zig   - Search functionality
│   ├── treesitter.zig - Tree-sitter parser wrapper
│   ├── undo.zig     - Undo/redo with tree history
│   └── window.zig   - Window management and splits
├── lsp/             - Language Server Protocol integration
│   ├── client.zig   - LSP client implementation
│   ├── handlers.zig - LSP message handlers
│   ├── process.zig  - LSP server process management
│   └── response_parser.zig - JSON-RPC response parsing
├── render/          - Terminal rendering pipeline
│   ├── buffer.zig   - Buffer rendering with colors
│   ├── gutter.zig   - Line numbers and diagnostics
│   └── markdown.zig - Markdown to plain text conversion
├── terminal/        - Terminal I/O and platform abstractions
├── treesitter/      - Tree-sitter C bindings
│   └── bindings.zig - Complete tree-sitter API bindings
└── main.zig         - Entry point

tests/
├── e2e/             - End-to-end persona-based tests
├── integration/     - Integration tests
├── unit/            - Unit tests for core components
├── fixtures/        - Test fixture files
└── helpers.zig      - Test utilities and mocks

queries/
├── zig/             - Zig syntax highlighting queries
├── rust/            - Rust syntax highlighting queries
├── go/              - Go syntax highlighting queries
├── python/          - Python syntax highlighting queries
└── c/               - C syntax highlighting queries
```

### Running Tests

```bash
# Run all tests
zig build test

# Run with verbose output
zig build test --summary all
```

### Code Formatting

```bash
# Format all source files
zig fmt src/

# Check formatting (CI requirement)
zig fmt --check src/
```

### Dependencies

- **[zio](https://github.com/lalinsky/zio)** (v0.4.0) - Async I/O framework built on libxev
- **[zigjr](https://github.com/williamw520/zigjr)** (v1.6.0) - JSON-RPC implementation for LSP
- **tree-sitter** (v0.25+) - Incremental parsing library for syntax highlighting

Dependencies are managed through `build.zig.zon` and fetched automatically during build. Tree-sitter must be installed separately (see installation instructions above).

## Architecture Highlights

### Rope Data Structure

Text is stored in a balanced tree of 512-1024 byte chunks, enabling:
- **O(log n) insert/delete** - Fast edits anywhere in large files
- **Efficient slicing** - Extract substrings without copying
- **Copy-on-write** - Zero-cost snapshots for undo/redo
- **UTF-8 aware** - Character indexing respects Unicode boundaries

### Prompt System

Interactive commands use a continuation-passing architecture:
1. Command initiates, sets pending state, shows prompt
2. Event loop remains responsive
3. User input dispatched to completion handler
4. Handler executes action, clears state

This design avoids blocking and enables universal escape-key cancellation.

### Event Loop

```
Input → Parse Key → Priority Dispatch:
                    1. Incremental search
                    2. Pending command
                    3. Normal command
                    ↓
                    Render → Output
```

The priority system ensures search and interactive commands capture input before normal command processing.

## Roadmap

### Current Status (November 2025)

**Implemented**:
- Core editing operations (insert, delete, navigation)
- Rope-based text buffer with undo/redo
- Modal editing system (normal, insert, select)
- Vim motions and text objects
- Find/till character motions with repeat
- Marks for position bookmarking
- Macro recording and playback
- Register system (named, numbered, system, black hole)
- Search with regex, options, and history
- **Tree-sitter syntax highlighting** with query-based highlighting for Zig, Rust, Go, Python, and C
- **Incremental parsing** with edit tracking for performance
- **LSP integration** with diagnostics, completion, hover, and go-to-definition
- **Window management** with horizontal and vertical splits
- Prompt system for interactive commands
- File finder and buffer management
- Configuration system (XDG-compliant, comprehensive settings)
- **Comprehensive test suite** with 99 tests (unit, integration, and e2e)
- Cross-platform support (Linux, macOS, Windows)

**In Progress**:
- Additional language grammar installation
- Plugin system
- Performance optimizations

**Planned**:
- Tabs and advanced window layouts
- Git integration (status, blame, diff)
- Snippet support
- Code actions and refactoring
- Debugger integration

## Testing

Aesop has a comprehensive test suite with 99 tests covering:

### Test Categories

- **Unit tests** (56 tests): Core components (rope, cursor, window, markdown, LSP parser)
- **Integration tests** (8 tests): Buffer editing, multi-line operations, clipboard, UTF-8
- **E2E tests** (43 tests): Complete workflows with persona-based scenarios

### Test Personas

The e2e test suite simulates real user workflows:

- **Developer persona** (8 tests): Code editing with LSP, multi-cursor, TDD workflow
- **Writer persona** (10 tests): Prose editing, markdown, search/replace, document navigation
- **Sysadmin persona** (10 tests): Config file editing, log monitoring, multi-file workflows
- **Failure/recovery** (15 tests): Edge cases, error handling, stress testing

### Running Tests

```bash
# Run all tests
zig build test

# All tests should pass with comprehensive coverage
# Current coverage: ~55% overall, ~90% critical path
```

## Contributing

Contributions are welcome! When submitting changes:

1. **Code style**: Run `zig fmt` before committing
2. **Tests**: Add tests for new features, ensure `zig build test` passes
3. **CI**: All GitHub Actions workflows must pass (Linux, macOS, Windows builds + formatting check)
4. **Documentation**: Update docs for user-facing features
5. **Commits**: Use clear, descriptive commit messages

Before starting work on major features, consider opening an issue to discuss the approach.

## License

MIT License - see [LICENSE](LICENSE) for details.

Copyright (c) 2025 Rand Arete
