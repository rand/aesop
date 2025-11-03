# Tree-sitter Grammar Installation Guide

**Purpose**: Step-by-step instructions for building and installing tree-sitter language grammars

**Status**: Required for syntax highlighting to work

---

## Overview

Aesop uses tree-sitter for fast, accurate syntax highlighting. The core tree-sitter library is installed via package manager, but language-specific grammars must be built and installed separately.

**Supported Languages**:
- Zig
- Rust
- Go
- Python
- C

---

## Prerequisites

**Required**:
- clang or gcc (C compiler)
- git
- make (optional, for convenience)

**macOS**:
```bash
# Compilers are included with Xcode Command Line Tools
xcode-select --install
```

**Linux (Debian/Ubuntu)**:
```bash
sudo apt-get install build-essential git
```

**Linux (Arch)**:
```bash
sudo pacman -S base-devel git
```

---

## Installation Process

Each grammar follows the same pattern:
1. Clone the grammar repository
2. Build the shared library
3. Copy to system library directory
4. Verify installation

### Step 1: Zig Grammar

```bash
# Clone repository
cd /tmp
git clone https://github.com/maxxnino/tree-sitter-zig
cd tree-sitter-zig

# Build shared library (macOS)
clang -shared -o libtree-sitter-zig.dylib -fPIC src/parser.c -I./src

# OR build shared library (Linux)
clang -shared -o libtree-sitter-zig.so -fPIC src/parser.c -I./src

# Copy to system library directory (macOS)
sudo cp libtree-sitter-zig.dylib /opt/homebrew/lib/

# OR copy to system library directory (Linux)
sudo cp libtree-sitter-zig.so /usr/local/lib/
sudo ldconfig  # Update library cache

# Verify
ls -la /opt/homebrew/lib/libtree-sitter-zig.dylib  # macOS
# OR
ls -la /usr/local/lib/libtree-sitter-zig.so        # Linux
```

### Step 2: Rust Grammar

```bash
# Clone repository
cd /tmp
git clone https://github.com/tree-sitter/tree-sitter-rust
cd tree-sitter-rust

# Build shared library (macOS)
clang -shared -o libtree-sitter-rust.dylib -fPIC src/parser.c src/scanner.c -I./src

# OR build shared library (Linux)
clang -shared -o libtree-sitter-rust.so -fPIC src/parser.c src/scanner.c -I./src

# Copy to system library directory (macOS)
sudo cp libtree-sitter-rust.dylib /opt/homebrew/lib/

# OR copy to system library directory (Linux)
sudo cp libtree-sitter-rust.so /usr/local/lib/
sudo ldconfig

# Verify
ls -la /opt/homebrew/lib/libtree-sitter-rust.dylib  # macOS
# OR
ls -la /usr/local/lib/libtree-sitter-rust.so        # Linux
```

### Step 3: Go Grammar

```bash
# Clone repository
cd /tmp
git clone https://github.com/tree-sitter/tree-sitter-go
cd tree-sitter-go

# Build shared library (macOS)
clang -shared -o libtree-sitter-go.dylib -fPIC src/parser.c -I./src

# OR build shared library (Linux)
clang -shared -o libtree-sitter-go.so -fPIC src/parser.c -I./src

# Copy to system library directory (macOS)
sudo cp libtree-sitter-go.dylib /opt/homebrew/lib/

# OR copy to system library directory (Linux)
sudo cp libtree-sitter-go.so /usr/local/lib/
sudo ldconfig

# Verify
ls -la /opt/homebrew/lib/libtree-sitter-go.dylib  # macOS
# OR
ls -la /usr/local/lib/libtree-sitter-go.so        # Linux
```

### Step 4: Python Grammar

```bash
# Clone repository
cd /tmp
git clone https://github.com/tree-sitter/tree-sitter-python
cd tree-sitter-python

# Build shared library (macOS)
clang -shared -o libtree-sitter-python.dylib -fPIC src/parser.c src/scanner.c -I./src

# OR build shared library (Linux)
clang -shared -o libtree-sitter-python.so -fPIC src/parser.c src/scanner.c -I./src

# Copy to system library directory (macOS)
sudo cp libtree-sitter-python.dylib /opt/homebrew/lib/

# OR copy to system library directory (Linux)
sudo cp libtree-sitter-python.so /usr/local/lib/
sudo ldconfig

# Verify
ls -la /opt/homebrew/lib/libtree-sitter-python.dylib  # macOS
# OR
ls -la /usr/local/lib/libtree-sitter-python.so        # Linux
```

### Step 5: C Grammar

```bash
# Clone repository
cd /tmp
git clone https://github.com/tree-sitter/tree-sitter-c
cd tree-sitter-c

# Build shared library (macOS)
clang -shared -o libtree-sitter-c.dylib -fPIC src/parser.c -I./src

# OR build shared library (Linux)
clang -shared -o libtree-sitter-c.so -fPIC src/parser.c -I./src

# Copy to system library directory (macOS)
sudo cp libtree-sitter-c.dylib /opt/homebrew/lib/

# OR copy to system library directory (Linux)
sudo cp libtree-sitter-c.so /usr/local/lib/
sudo ldconfig

# Verify
ls -la /opt/homebrew/lib/libtree-sitter-c.dylib  # macOS
# OR
ls -la /usr/local/lib/libtree-sitter-c.so        # Linux
```

---

## Verification

After installing all grammars, verify they're accessible:

**macOS**:
```bash
ls -la /opt/homebrew/lib/libtree-sitter-*.dylib

# Expected output:
# -rw-r--r--  1 root  wheel  libtree-sitter-c.dylib
# -rw-r--r--  1 root  wheel  libtree-sitter-go.dylib
# -rw-r--r--  1 root  wheel  libtree-sitter-python.dylib
# -rw-r--r--  1 root  wheel  libtree-sitter-rust.dylib
# -rw-r--r--  1 root  wheel  libtree-sitter-zig.dylib
```

**Linux**:
```bash
ls -la /usr/local/lib/libtree-sitter-*.so

# Expected output:
# -rw-r--r--  1 root root libtree-sitter-c.so
# -rw-r--r--  1 root root libtree-sitter-go.so
# -rw-r--r--  1 root root libtree-sitter-python.so
# -rw-r--r--  1 root root libtree-sitter-rust.so
# -rw-r--r--  1 root root libtree-sitter-zig.so
```

---

## Building Aesop with Grammars

Once all grammars are installed:

```bash
cd ~/src/aesop
zig build

# If successful, syntax highlighting will work
./zig-out/bin/aesop test.zig
```

**Expected behavior**: Syntax highlighting for supported languages will be colorized

---

## Troubleshooting

### Build Error: Cannot find library

**Error**:
```
error: ld: can't link with a main executable file 'libtree-sitter-zig.dylib'
```

**Solution**: Grammar not installed or wrong permissions
```bash
# Check if file exists and is readable
ls -la /opt/homebrew/lib/libtree-sitter-zig.dylib

# Fix permissions if needed
sudo chmod 644 /opt/homebrew/lib/libtree-sitter-zig.dylib
```

### Compilation Error: Missing scanner.c

**Error**:
```
clang: error: no such file or directory: 'src/scanner.c'
```

**Solution**: Not all grammars have scanner.c - it's optional
```bash
# Omit scanner.c if it doesn't exist
clang -shared -o libtree-sitter-go.dylib -fPIC src/parser.c -I./src
```

### Runtime Error: Library not found

**Error (Linux)**:
```
error while loading shared libraries: libtree-sitter-zig.so: cannot open shared object file
```

**Solution**: Update library cache
```bash
sudo ldconfig
```

### Syntax Highlighting Not Working

**Check**:
1. Grammars installed correctly (ls command above)
2. Build successful (zig build)
3. File extension matches supported language (.zig, .rs, .go, .py, .c)
4. Query files exist (queries/zig/highlights.scm, etc.)

**Test**:
```bash
# Open a file with syntax highlighting
./zig-out/bin/aesop src/main.zig

# Should see colorized keywords, functions, types, etc.
```

---

## Automated Installation Script

For convenience, save this as `install_grammars.sh`:

```bash
#!/bin/bash
set -e

# Detect platform
if [[ "$OSTYPE" == "darwin"* ]]; then
    LIB_EXT="dylib"
    LIB_DIR="/opt/homebrew/lib"
else
    LIB_EXT="so"
    LIB_DIR="/usr/local/lib"
fi

# Grammar repositories
declare -A GRAMMARS=(
    ["zig"]="https://github.com/maxxnino/tree-sitter-zig"
    ["rust"]="https://github.com/tree-sitter/tree-sitter-rust"
    ["go"]="https://github.com/tree-sitter/tree-sitter-go"
    ["python"]="https://github.com/tree-sitter/tree-sitter-python"
    ["c"]="https://github.com/tree-sitter/tree-sitter-c"
)

# Grammars with scanner.c
SCANNER_LANGS=("rust" "python")

cd /tmp

for lang in "${!GRAMMARS[@]}"; do
    echo "Installing tree-sitter-$lang..."

    # Clone
    rm -rf "tree-sitter-$lang"
    git clone "${GRAMMARS[$lang]}"
    cd "tree-sitter-$lang"

    # Build
    if [[ " ${SCANNER_LANGS[@]} " =~ " ${lang} " ]]; then
        clang -shared -o "libtree-sitter-$lang.$LIB_EXT" -fPIC src/parser.c src/scanner.c -I./src
    else
        clang -shared -o "libtree-sitter-$lang.$LIB_EXT" -fPIC src/parser.c -I./src
    fi

    # Install
    sudo cp "libtree-sitter-$lang.$LIB_EXT" "$LIB_DIR/"

    cd /tmp
    echo "✓ tree-sitter-$lang installed"
done

# Update library cache (Linux only)
if [[ "$OSTYPE" != "darwin"* ]]; then
    sudo ldconfig
fi

echo "All grammars installed successfully!"
echo "You can now build Aesop with: zig build"
```

**Usage**:
```bash
chmod +x install_grammars.sh
./install_grammars.sh
```

---

## Uninstallation

To remove installed grammars:

**macOS**:
```bash
sudo rm /opt/homebrew/lib/libtree-sitter-zig.dylib
sudo rm /opt/homebrew/lib/libtree-sitter-rust.dylib
sudo rm /opt/homebrew/lib/libtree-sitter-go.dylib
sudo rm /opt/homebrew/lib/libtree-sitter-python.dylib
sudo rm /opt/homebrew/lib/libtree-sitter-c.dylib
```

**Linux**:
```bash
sudo rm /usr/local/lib/libtree-sitter-zig.so
sudo rm /usr/local/lib/libtree-sitter-rust.so
sudo rm /usr/local/lib/libtree-sitter-go.so
sudo rm /usr/local/lib/libtree-sitter-python.so
sudo rm /usr/local/lib/libtree-sitter-c.so
sudo ldconfig
```

---

## Next Steps

After installing grammars:
1. Build Aesop: `zig build`
2. Test highlighting: `./zig-out/bin/aesop test.zig`
3. Report issues: https://github.com/rand/aesop/issues

---

## See Also

- [Building with Tree-sitter](BUILDING_WITH_TREE_SITTER.md) - Architecture and integration details
- [User Guide](USER_GUIDE.md) - Using syntax highlighting features
- [API Documentation](API.md) - Extending with custom languages
