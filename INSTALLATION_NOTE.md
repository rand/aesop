# Installation Note

## Binary Location

Aesop uses a wrapper script installation:

```
~/.local/bin/aesop          → Wrapper script (sets DYLD_LIBRARY_PATH)
~/.local/bin/aesop-bin      → Actual binary (3.4 MB)
```

## Installing After Build

After building with `zig build`, install the new binary:

```bash
cp zig-out/bin/aesop ~/.local/bin/aesop-bin
```

The wrapper script at `~/.local/bin/aesop` automatically:
- Sets `DYLD_LIBRARY_PATH=$HOME/lib` for tree-sitter libraries
- Executes the actual binary at `~/.local/bin/aesop-bin`

## Verification

Check installed version timestamp:
```bash
ls -lh ~/.local/bin/aesop-bin
```

Compare with build:
```bash
ls -lh zig-out/bin/aesop
```

## Theme Changes Now Active

✅ The beautiful Yonce Dark theme is now active when you run `aesop` from any terminal!
