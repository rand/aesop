# Tree-sitter Integration Plan

## Current State

Aesop currently uses a basic keyword-based syntax highlighter implemented in:
- `src/editor/highlight.zig` - Core tokenizer with keyword matching
- `src/editor/treesitter.zig` - Wrapper providing tree-sitter-like API

The current implementation provides adequate highlighting for common cases but lacks:
- Accurate function/method detection
- Scope-aware highlighting
- Incremental re-parsing
- Language-specific query support

## Why Tree-sitter?

Tree-sitter is an incremental parsing library that provides:
1. **Accurate syntax analysis** - Full parse trees, not heuristics
2. **Incremental updates** - Fast re-parsing on edits
3. **Language queries** - Powerful pattern matching for highlighting/folding
4. **Error recovery** - Graceful handling of incomplete code
5. **Multi-language support** - 40+ maintained grammar repositories

## Integration Requirements

### 1. Build System Changes

**Add tree-sitter as dependency:**
```zig
// build.zig
const tree_sitter = b.dependency("tree-sitter", .{
    .target = target,
    .optimize = optimize,
});

exe.linkLibrary(tree_sitter.artifact("tree-sitter"));
```

**Fetch tree-sitter:**
```zig
// build.zig.zon
.dependencies = .{
    .@"tree-sitter" = .{
        .url = "https://github.com/tree-sitter/tree-sitter/archive/v0.20.8.tar.gz",
        .hash = "<sha256>",
    },
},
```

### 2. Language Grammar Management

Each language requires a compiled grammar:

**Option A: Bundled grammars (recommended)**
- Bundle pre-compiled `.so`/`.dylib`/`.dll` files
- Advantages: No compile-time dependency, faster builds
- Disadvantages: Platform-specific binaries, larger repo

**Option B: Compile-time grammars**
- Add language repositories as build dependencies
- Compile each grammar during build
- Advantages: Cross-platform, cleaner
- Disadvantages: Slower builds, complex build script

**Required grammars:**
- tree-sitter-zig
- tree-sitter-rust
- tree-sitter-go
- tree-sitter-python
- tree-sitter-javascript
- tree-sitter-typescript
- tree-sitter-c

### 3. C API Bindings

Create Zig bindings for tree-sitter C API:

```zig
// src/treesitter/bindings.zig
pub const TSParser = opaque {};
pub const TSTree = opaque {};
pub const TSNode = extern struct {
    context: [4]u32,
    id: ?*const anyopaque,
    tree: ?*const TSTree,
};

pub extern fn ts_parser_new() ?*TSParser;
pub extern fn ts_parser_delete(parser: *TSParser) void;
pub extern fn ts_parser_set_language(parser: *TSParser, language: *const TSLanguage) bool;
pub extern fn ts_parser_parse_string(
    parser: *TSParser,
    old_tree: ?*TSTree,
    string: [*]const u8,
    length: u32,
) ?*TSTree;
// ... more bindings
```

### 4. Parser Wrapper

Implement high-level Zig wrapper:

```zig
// src/treesitter/parser.zig
pub const Parser = struct {
    handle: *c.TSParser,
    language: Language,
    current_tree: ?*c.TSTree,

    pub fn init(allocator: Allocator, language: Language) !Parser {
        const handle = c.ts_parser_new() orelse return error.ParserInit;

        const lang_fn = language.getLanguageFunction();
        if (!c.ts_parser_set_language(handle, lang_fn())) {
            c.ts_parser_delete(handle);
            return error.InvalidLanguage;
        }

        return Parser{
            .handle = handle,
            .language = language,
            .current_tree = null,
        };
    }

    pub fn parse(self: *Parser, text: []const u8) !void {
        const old_tree = self.current_tree;
        defer if (old_tree) |tree| c.ts_tree_delete(tree);

        self.current_tree = c.ts_parser_parse_string(
            self.handle,
            old_tree,
            text.ptr,
            @intCast(text.len),
        ) orelse return error.ParseFailed;
    }
};
```

### 5. Highlighting Queries

Each language needs a highlighting query file:

```scheme
; queries/zig/highlights.scm
(function_declaration name: (identifier) @function)
(call_expression function: (identifier) @function.call)
(type_declaration name: (identifier) @type)
"const" @keyword
"fn" @keyword
(string_literal) @string
(number_literal) @number
```

### 6. Integration Points

**In Editor:**
```zig
// src/editor/editor.zig
pub const Editor = struct {
    parser: ?TreeSitter.Parser,

    pub fn init(allocator: Allocator) !Editor {
        const language = Language.fromFilename(filepath);
        const parser = try TreeSitter.Parser.init(allocator, language);

        return Editor{ .parser = parser, ... };
    }

    fn onBufferEdit(self: *Editor, edit: Edit) !void {
        // Re-parse incrementally
        try self.parser.?.edit(edit);
        try self.parser.?.parse(self.buffer.getText());

        // Invalidate highlight cache
        self.highlight_cache.clear();
    }
};
```

## Implementation Phases

### Phase 1: Build System (1-2 days)
- [ ] Add tree-sitter dependency to build.zig
- [ ] Create C bindings module
- [ ] Test basic parser creation

### Phase 2: Core Integration (2-3 days)
- [ ] Implement Parser wrapper
- [ ] Add language loading
- [ ] Test parsing Zig files

### Phase 3: Highlighting (2-3 days)
- [ ] Load highlight queries
- [ ] Query API bindings
- [ ] Convert to HighlightToken
- [ ] Integrate with renderer

### Phase 4: Multi-Language (1-2 days)
- [ ] Add Rust grammar
- [ ] Add Go grammar
- [ ] Add Python grammar
- [ ] Language auto-detection

### Phase 5: Incremental Parsing (1-2 days)
- [ ] Implement edit tracking
- [ ] TSInput for rope buffer
- [ ] Performance testing

**Total estimated effort: 7-12 days**

## Alternative: Enhanced Keyword Highlighter

For MVP/demo purposes, we can significantly improve the current highlighter:

**Improvements:**
- Multi-language keyword support (Rust, Go, Python)
- Better function detection (look for `(` after identifier)
- Multi-line comment support
- Raw string literals
- Regex literals (JavaScript)
- Decorators (Python)

**Pros:**
- No external dependencies
- Much faster to implement (1-2 hours)
- Adequate for demonstration
- Easier to maintain

**Cons:**
- Less accurate than tree-sitter
- No structural analysis
- Higher error rate on complex code

## Recommendation

**Short-term (now):** Enhance keyword highlighter
- Add multi-language support
- Improve heuristics
- Document limitations

**Medium-term (post-MVP):** Tree-sitter integration
- After core editor features stabilize
- When performance becomes critical
- When accurate refactoring tools are needed

## References

- [Tree-sitter Documentation](https://tree-sitter.github.io/tree-sitter/)
- [Tree-sitter Zig Grammar](https://github.com/maxxnino/tree-sitter-zig)
- [Helix Editor Tree-sitter Integration](https://github.com/helix-editor/helix/tree/master/helix-core/src/syntax)
- [Zed Editor Tree-sitter Usage](https://zed.dev/blog/syntax-aware-editing)
