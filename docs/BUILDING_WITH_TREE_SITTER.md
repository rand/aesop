# Building with Tree-sitter

## Overview

Aesop uses tree-sitter for accurate syntax highlighting and code analysis. This document explains how to set up tree-sitter for development and building.

---

## Prerequisites

Tree-sitter library (v0.20.8 or later) must be available during compilation.

---

## Option 1: System Installation (Recommended for Development)

### macOS (Homebrew)
```bash
brew install tree-sitter
```

### Linux (Ubuntu/Debian)
```bash
sudo apt-get install libtree-sitter-dev
```

### Linux (Arch)
```bash
sudo pacman -S tree-sitter
```

### From Source
```bash
git clone https://github.com/tree-sitter/tree-sitter.git
cd tree-sitter
make
sudo make install
```

---

## Option 2: Build as Part of Aesop (TODO)

Future work will embed tree-sitter compilation in `build.zig` to eliminate the system dependency requirement.

**Status**: Planned for Phase 2.1 completion

**Approach**:
1. Add tree-sitter source as git submodule or fetch tarball
2. Compile tree-sitter C library in build.zig
3. Link statically with Aesop

---

## Language Grammars

Each language requires a compiled grammar library.

### Required Grammars

- **tree-sitter-zig**: Zig language support
- **tree-sitter-rust**: Rust language support
- **tree-sitter-go**: Go language support
- **tree-sitter-python**: Python language support
- **tree-sitter-c**: C language support

### Installation Methods

#### Option A: System Installation (Development)

```bash
# Clone grammar repositories
git clone https://github.com/maxxnino/tree-sitter-zig.git
git clone https://github.com/tree-sitter/tree-sitter-rust.git
git clone https://github.com/tree-sitter/tree-sitter-go.git
git clone https://github.com/tree-sitter/tree-sitter-python.git
git clone https://github.com/tree-sitter/tree-sitter-c.git

# Build and install each grammar
cd tree-sitter-zig
make
sudo make install

# Repeat for each grammar
```

#### Option B: Bundle with Aesop (Production)

Future releases will bundle pre-compiled grammars or compile them during build.

---

## Verifying Installation

### Check tree-sitter Library

```bash
# macOS
ls -la /opt/homebrew/lib/libtree-sitter.*

# Linux
ls -la /usr/lib/x86_64-linux-gnu/libtree-sitter.*
```

### Check Grammar Libraries

```bash
# Look for libtree-sitter-*.so or libtree-sitter-*.dylib
ls -la /usr/local/lib/libtree-sitter-*
```

### Test Compilation

```bash
cd /Users/rand/src/aesop
zig build

# Should compile without tree-sitter errors
# Note: Parser functionality requires grammars at runtime
```

---

## Build Configuration

### Current Status (Phase 2.1)

**File**: `build.zig`
- Tree-sitter linking not yet configured
- Will be added in Phase 2.1

**File**: `src/treesitter/bindings.zig`
- ✅ Complete C API bindings
- Ready for integration

**File**: `src/editor/treesitter.zig`
- Currently a stub implementation
- Will be replaced in Phase 2.2

### Planned Changes

```zig
// build.zig (Phase 2.1)
exe.linkSystemLibrary("tree-sitter");
exe.addIncludePath(.{ .path = "/usr/local/include" });
exe.addLibraryPath(.{ .path = "/usr/local/lib" });

// Or with dependency (alternative approach)
const tree_sitter = b.dependency("tree_sitter", .{
    .target = target,
    .optimize = optimize,
});
exe.linkLibrary(tree_sitter.artifact("tree-sitter"));
```

---

## Troubleshooting

### "libtree-sitter not found" Error

**Problem**: Linker cannot find tree-sitter library

**Solutions**:
1. Install tree-sitter system-wide (see Option 1 above)
2. Set `LD_LIBRARY_PATH` (Linux) or `DYLD_LIBRARY_PATH` (macOS):
   ```bash
   export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
   ```
3. Update `build.zig` with explicit library path

### "tree_sitter_zig not defined" Error

**Problem**: Language grammar not available

**Solutions**:
1. Install grammar libraries (see Language Grammars above)
2. Grammar loading will be optional in Phase 2.2 (graceful fallback)

### Build Succeeds but Parsing Fails at Runtime

**Problem**: Grammars not in library search path

**Solutions**:
1. Install grammars to standard location (`/usr/local/lib`)
2. Add runtime library path to environment
3. Use bundled grammars (Phase 2.4)

---

## Development Workflow

### Without Tree-sitter (Fallback Mode)

Aesop currently uses keyword-based highlighting as a fallback:
- No tree-sitter dependency required for basic functionality
- Located in `src/editor/highlight.zig`
- Supports Zig, Rust, Go, Python, C

### With Tree-sitter (Future)

Full tree-sitter integration after Phase 2 completion:
- Accurate syntax highlighting
- Incremental re-parsing
- Syntax-aware text objects
- Code folding
- Error recovery

---

## CI/CD Considerations

### GitHub Actions

```yaml
# .github/workflows/ci.yml
- name: Install tree-sitter
  run: |
    # Ubuntu
    sudo apt-get install -y libtree-sitter-dev

    # Or build from source
    git clone https://github.com/tree-sitter/tree-sitter.git
    cd tree-sitter && make && sudo make install

- name: Install language grammars
  run: |
    # Install required grammars
    # (script to be added in Phase 2.4)
```

### Docker

```dockerfile
FROM alpine:latest
RUN apk add --no-cache tree-sitter tree-sitter-dev
# Add grammar installation steps
```

---

## Future Work

### Phase 2.1 Goals

- [ ] Add tree-sitter to build.zig with proper linking
- [ ] Handle library search paths cross-platform
- [ ] Verify compilation on Linux, macOS, Windows

### Phase 2.2 Goals

- [ ] Implement Parser wrapper using bindings.zig
- [ ] Add Zig grammar loading
- [ ] Graceful fallback if grammar unavailable

### Phase 2.4 Goals

- [ ] Bundle pre-compiled grammar libraries
- [ ] Auto-download grammars on first run (optional)
- [ ] Platform-specific library packaging

---

## References

- [Tree-sitter Documentation](https://tree-sitter.github.io/tree-sitter/)
- [Using Parsers Guide](https://tree-sitter.github.io/tree-sitter/using-parsers)
- [Creating Parsers Guide](https://tree-sitter.github.io/tree-sitter/creating-parsers)
- [Tree-sitter Zig Grammar](https://github.com/maxxnino/tree-sitter-zig)
- [Zig Build System Docs](https://ziglang.org/documentation/master/#Zig-Build-System)

---

## Questions?

For build issues, check:
1. This document's troubleshooting section
2. `docs/TREE_SITTER_INTEGRATION.md` for integration details
3. `docs/NEXT_STEPS.md` for development roadmap
