# Aesop Editor - Installation Guide

Complete guide for installing, configuring, and uninstalling Aesop editor.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Installation](#quick-installation)
- [Installation Options](#installation-options)
- [Configuration](#configuration)
- [Uninstallation](#uninstallation)
- [Manual Installation](#manual-installation)
- [Troubleshooting](#troubleshooting)
- [What Gets Installed](#what-gets-installed)

---

## Prerequisites

### Required

- **Zig Compiler** (version 0.15.1 or compatible)
  - Download: https://ziglang.org/download/
  - Check version: `zig version`

### Optional (but recommended)

- **Tree-sitter Libraries** for syntax highlighting
  - Required for full syntax highlighting support
  - Libraries should be placed in `~/lib/`
  - Expected format: `libtree-sitter-<language>.dylib` (macOS)

Aesop includes grammars for: `zig`, `rust`, `go`, `python`, `c`

---

## Quick Installation

```bash
# Clone or navigate to aesop directory
cd /path/to/aesop

# Run the installer
./install.sh

# Follow interactive prompts
```

That's it! The installer will:
1. Check prerequisites
2. Build the editor
3. Install to `~/.local/bin`
4. Optionally create a config file
5. Verify the installation

---

## Installation Options

### Standard Installation

Builds and installs in one step:

```bash
./install.sh
```

### Install from Existing Build

If you've already run `zig build`:

```bash
./install.sh --skip-build
```

### Help

```bash
./install.sh --help
```

---

## Configuration

### Config File Location

`~/.config/aesop/config.conf`

### Creating a Config File

During installation, you'll be prompted to create a config file. You can also create one manually:

```bash
# Copy example config
cp examples/config.conf.example ~/.config/aesop/config.conf

# Edit to your preferences
<your-editor> ~/.config/aesop/config.conf
```

### Configuration Format

Simple `key=value` format:

```conf
# Editor behavior
tab_width=4
expand_tabs=true
line_numbers=true

# Visual settings
theme_name=yonce
syntax_highlighting=true
highlight_current_line=true

# Search settings
search_case_sensitive=false
search_wrap_around=true
```

See `examples/config.conf.example` for all available options with detailed documentation.

### Default Behavior

If no config file exists, Aesop uses sensible defaults:
- 4-space tabs (expanded to spaces)
- Line numbers enabled
- Syntax highlighting enabled
- Yonce Dark theme
- Auto-indent enabled
- And more...

---

## Uninstallation

### Safe Uninstall

```bash
./uninstall.sh
```

The uninstaller:
1. Detects installed components
2. Backs up your configuration to `~/.local/share/aesop-backups/`
3. Removes binaries (`aesop` wrapper and `aesop-bin`)
4. Asks if you want to remove config directory (default: NO)
5. Asks if you want to remove backup (default: NO)

### What Gets Removed

**Automatically removed:**
- `~/.local/bin/aesop` (wrapper script)
- `~/.local/bin/aesop-bin` (main binary)

**Kept by default** (interactive prompt):
- `~/.config/aesop/` (your configuration)
- `~/.local/share/aesop-backups/` (config backups)

### Manual Removal

If you prefer manual removal:

```bash
# Remove binaries
rm ~/.local/bin/aesop
rm ~/.local/bin/aesop-bin

# Remove config (optional)
rm -rf ~/.config/aesop

# Remove backups (optional)
rm -rf ~/.local/share/aesop-backups
```

---

## Manual Installation

If you prefer not to use the install script:

### 1. Build the Binary

```bash
# Set library path for tree-sitter (macOS)
export DYLD_LIBRARY_PATH=$HOME/lib

# Build
zig build

# Verify build
ls -lh zig-out/bin/aesop
```

### 2. Create Installation Directory

```bash
mkdir -p ~/.local/bin
```

### 3. Create Wrapper Script

Create `~/.local/bin/aesop` with the following content:

```bash
#!/bin/bash
# Aesop wrapper script - sets environment for tree-sitter libraries
export DYLD_LIBRARY_PATH="$HOME/lib"
exec "$HOME/.local/bin/aesop-bin" "$@"
```

Make it executable:

```bash
chmod +x ~/.local/bin/aesop
```

### 4. Copy Binary

```bash
cp zig-out/bin/aesop ~/.local/bin/aesop-bin
chmod +x ~/.local/bin/aesop-bin
```

### 5. Configure PATH

Add to your shell config (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Reload your shell:

```bash
source ~/.zshrc  # or source ~/.bashrc
```

### 6. Create Config Directory (Optional)

```bash
mkdir -p ~/.config/aesop
cp examples/config.conf.example ~/.config/aesop/config.conf
```

---

## Troubleshooting

### Installation Issues

#### "Zig compiler not found"

**Solution:** Install Zig from https://ziglang.org/download/

```bash
# Verify installation
zig version
```

#### "Build failed"

**Check:**
1. Zig version compatibility (0.15.1 recommended)
2. Build log at `/tmp/aesop_build.log`
3. Tree-sitter library path

**Try:**
```bash
# Clean build
rm -rf zig-out zig-cache
DYLD_LIBRARY_PATH=~/lib zig build
```

#### "Tree-sitter libraries not found"

**Symptoms:**
- Warning during installation
- No syntax highlighting when running aesop

**Solution:**
Install tree-sitter grammars to `~/lib/`:

```bash
mkdir -p ~/lib
# Place .dylib files for each language in ~/lib/
# Example: libtree-sitter-zig.dylib, libtree-sitter-rust.dylib, etc.
```

Aesop will still work without tree-sitter, but syntax highlighting will be limited.

### Runtime Issues

#### "Command not found: aesop"

**Solution:** Ensure `~/.local/bin` is in your PATH:

```bash
# Check PATH
echo $PATH | grep -q "$HOME/.local/bin" && echo "In PATH" || echo "Not in PATH"

# Add to PATH (add to ~/.zshrc or ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"

# Reload shell
source ~/.zshrc
```

#### "Library not loaded: libtree-sitter-*.dylib"

**Solution:** Tree-sitter libraries must be in `~/lib/`:

```bash
# Check library directory
ls ~/lib/libtree-sitter-*.dylib

# If missing, install tree-sitter grammars
# Or run aesop through wrapper script
~/.local/bin/aesop
```

The wrapper script automatically sets `DYLD_LIBRARY_PATH`. If you're running the binary directly (`aesop-bin`), use the wrapper instead (`aesop`).

#### "Config file errors"

**Symptoms:**
- Editor fails to start
- Error messages about configuration

**Solution:**

```bash
# Backup current config
mv ~/.config/aesop/config.conf ~/.config/aesop/config.conf.backup

# Use example config
cp examples/config.conf.example ~/.config/aesop/config.conf

# Or remove config to use defaults
rm ~/.config/aesop/config.conf
```

#### "Permission denied"

**Solution:** Ensure scripts and binaries are executable:

```bash
# Installation scripts
chmod +x install.sh uninstall.sh

# Installed binaries
chmod +x ~/.local/bin/aesop
chmod +x ~/.local/bin/aesop-bin
```

### Performance Issues

#### Slow startup or editing

**Check:**
1. Config values (`~/.config/aesop/config.conf`):
   - `max_undo_history` (lower = less memory)
   - `syntax_highlighting` (disable if slow)
   - `max_cursors` (lower = better performance)

2. File size - very large files may be slow

**Try:**
```bash
# Disable syntax highlighting for large files
syntax_highlighting=false
```

---

## What Gets Installed

### Files Created

| Path | Description | Size |
|------|-------------|------|
| `~/.local/bin/aesop` | Wrapper script (sets environment) | ~200 bytes |
| `~/.local/bin/aesop-bin` | Main binary | ~3.4 MB |
| `~/.config/aesop/` | Config directory (optional) | - |
| `~/.config/aesop/config.conf` | User configuration (optional) | ~2 KB |

### Total Disk Usage

- **Binaries:** ~3.4 MB
- **Config:** ~2 KB (if created)
- **Total:** ~3.4 MB

### System Modifications

- Adds files to `~/.local/bin` (no system directories modified)
- May prompt to add `~/.local/bin` to PATH (manual step)
- No root/sudo required
- No system-wide changes
- Completely contained in user home directory

### Dependencies

**Runtime dependencies:**
- Tree-sitter libraries in `~/lib/` (optional, for syntax highlighting)

**No other runtime dependencies** - statically linked binary.

---

## Platform Support

### macOS

Fully supported (primary development platform):
- Apple Silicon (arm64)
- Intel (x86_64)

### Linux

Supported with minor adjustments:
- Change `DYLD_LIBRARY_PATH` to `LD_LIBRARY_PATH` in wrapper script
- Tree-sitter libraries use `.so` extension instead of `.dylib`

### Windows

Not currently supported. Cross-platform support may be added in future versions.

---

## Advanced Topics

### Multiple Installations

To install different versions side-by-side:

1. Use different installation directories
2. Modify `INSTALL_DIR` in install script
3. Use different binary names

Example:
```bash
# Edit install.sh
INSTALL_DIR="$HOME/.local/bin/aesop-dev"
WRAPPER_PATH="$INSTALL_DIR/aesop-dev"
```

### Building with Different Zig Versions

Aesop targets Zig 0.15.1. For other versions:

```bash
# Use specific Zig version
/path/to/zig-0.15.1/zig build
```

### Tree-sitter Grammar Management

To add more language grammars:

1. Build or download tree-sitter grammar
2. Copy `.dylib` to `~/lib/`
3. Naming: `libtree-sitter-<language>.dylib`
4. Restart aesop

---

## Getting Help

- **Installation issues:** Check [Troubleshooting](#troubleshooting) section
- **Configuration:** See `examples/config.conf.example`
- **Bug reports:** Create issue with `/tmp/aesop_build.log` if build fails
- **Feature requests:** Describe use case and desired behavior

---

## Quick Reference

```bash
# Install
./install.sh

# Install (skip build)
./install.sh --skip-build

# Uninstall
./uninstall.sh

# Run editor
aesop
aesop filename.txt

# Config file
~/.config/aesop/config.conf

# Example config
examples/config.conf.example

# Build manually
DYLD_LIBRARY_PATH=~/lib zig build
```

---

**Installation complete!** Enjoy using Aesop with the beautiful Yonce Dark theme. ✨
