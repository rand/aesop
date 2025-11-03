# Next Steps for Aesop 0.9 Release

**Updated**: November 3, 2025
**Current Status**: Phase 1 Complete, Ready for Phase 2 (Tree-sitter)

---

## Quick Start

If you're ready to continue immediately, start with:

```bash
# Review progress
cat docs/PROGRESS_PHASE_1.md

# Check current todos
# (All Phase 1 items complete)

# Begin Phase 2.1
cd /Users/rand/src/aesop
# Follow steps in docs/TREE_SITTER_INTEGRATION.md
```

---

## Recommended Session Structure

### Session 1: Test Infrastructure (Phase 1C)
**Duration**: 2-4 hours
**Goal**: Set up comprehensive testing framework

**Tasks**:
1. Create `tests/` directory structure:
   ```
   tests/
   ├── unit/           # Individual component tests
   ├── integration/    # Cross-component tests
   ├── e2e/           # Full workflow tests
   ├── fixtures/      # Test data (sample files, LSP responses)
   └── helpers.zig    # Test utilities
   ```

2. Create test helpers:
   - Mock terminal (fake input/output)
   - Buffer builders (quick test setup)
   - Assertion utilities (custom test helpers)
   - LSP response mocks

3. Add persona definitions:
   - Developer workflow (code editing, LSP, refactoring)
   - Writer workflow (prose editing, search, marks)
   - Sysadmin workflow (config files, multi-buffer, splits)

4. Set up fixtures:
   - Sample Zig/Rust/Python files for parsing
   - Mock LSP completion/diagnostic/hover responses
   - Edge case inputs (Unicode, large files, etc.)

**Output**: Test framework ready for Phase 2-3 validation

---

### Sessions 2-6: Tree-sitter Integration (Phase 2)
**Duration**: 7-12 days (can be split into 5-6 focused sessions)
**Goal**: Replace keyword highlighter with tree-sitter

#### Session 2: Build System (Phase 2.1)
**Duration**: 4-6 hours

1. Add tree-sitter to `build.zig.zon`:
   ```zig
   .dependencies = .{
       .@"tree-sitter" = .{
           .url = "https://github.com/tree-sitter/tree-sitter/archive/v0.20.8.tar.gz",
           .hash = "<calculate_hash>",
       },
   },
   ```

2. Update `build.zig`:
   ```zig
   const tree_sitter = b.dependency("tree-sitter", .{
       .target = target,
       .optimize = optimize,
   });
   exe.linkLibrary(tree_sitter.artifact("tree-sitter"));
   ```

3. Create `src/treesitter/bindings.zig`:
   - TSParser, TSTree, TSNode extern structs
   - Function declarations for C API
   - Error handling wrappers

4. Test basic parser lifecycle:
   ```zig
   test "create and destroy parser" {
       const parser = c.ts_parser_new();
       defer c.ts_parser_delete(parser);
       try testing.expect(parser != null);
   }
   ```

**Commit**: "Phase 2.1: Add tree-sitter build system and C bindings"

---

#### Session 3: Core Parser (Phase 2.2)
**Duration**: 6-8 hours

1. Replace `src/editor/treesitter.zig` stub with real implementation
2. Implement Parser wrapper:
   - init/deinit with language selection
   - parse() method
   - Tree ownership and lifecycle
3. Add Zig grammar (tree-sitter-zig)
4. Test parsing Zig source files
5. Verify tree structure and node traversal

**Tests**:
- Parse valid Zig code
- Parse incomplete code (error recovery)
- Incremental parse updates

**Commit**: "Phase 2.2: Implement core Parser wrapper with Zig grammar"

---

#### Session 4: Highlighting Queries (Phase 2.3)
**Duration**: 6-8 hours

1. Create `queries/zig/highlights.scm`:
   ```scheme
   (function_declaration name: (identifier) @function)
   (call_expression function: (identifier) @function.call)
   "const" @keyword
   (string_literal) @string
   ```

2. Implement query API bindings:
   - TSQuery creation from S-expression
   - Query execution on tree nodes
   - Capture extraction

3. Convert captures to TokenType:
   - Map @function → TokenType.function_name
   - Map @keyword → TokenType.keyword
   - etc.

4. Integrate with renderer:
   - Replace tokenizeLine() calls
   - Use tree-sitter tokens instead
   - Test visual output

**Commit**: "Phase 2.3: Add highlighting queries and renderer integration"

---

#### Session 5: Multi-Language (Phase 2.4)
**Duration**: 4-6 hours

1. Add grammars for Rust, Go, Python, C
2. Create highlight queries for each language
3. Update Language.fromFilename() to load correct grammar
4. Test highlighting accuracy for each language
5. Benchmark performance vs keyword highlighter

**Tests**:
- Parse and highlight Rust code
- Parse and highlight Go code
- Parse and highlight Python code
- Parse and highlight C code

**Commit**: "Phase 2.4: Add multi-language support (Rust, Go, Python, C)"

---

#### Session 6: Incremental Parsing (Phase 2.5)
**Duration**: 4-6 hours

1. Track edits in rope operations:
   - Record (start_byte, old_end_byte, new_end_byte)
   - Pass to ts_tree_edit()

2. Implement TSInput for rope:
   - read() callback fetches from rope chunks
   - encoding() returns UTF8
   - Efficient chunk-based reading

3. Test incremental updates:
   - Edit middle of file, verify only affected nodes re-parse
   - Insert/delete text, check correctness
   - Benchmark re-parse time

4. Performance validation:
   - Large file edits (>10k lines)
   - Rapid successive edits
   - Memory usage tracking

**Commit**: "Phase 2.5: Implement incremental parsing with rope integration"

---

### Sessions 7-9: Testing (Phase 3)
**Duration**: 3-4 days
**Goal**: Achieve 70%+ overall coverage, 90%+ critical path

#### Session 7: Unit Tests
**Duration**: 6-8 hours

- Rope rebalancing tests
- Undo tree branching tests
- Window manager edge cases
- LSP response parser error handling
- Markdown converter edge cases
- Tree-sitter parser lifecycle
- Query matching accuracy

**Commit**: "Phase 3.1: Add comprehensive unit test coverage"

---

#### Session 8: Integration Tests
**Duration**: 6-8 hours

- LSP workflows (initialize → didOpen → completion → rename)
- Buffer management with window splits
- Tree-sitter parsing with buffer edits
- Diagnostic publishing and display
- Signature help triggers and dismissal

**Commit**: "Phase 3.2: Add integration tests for cross-component features"

---

#### Session 9: E2E & Persona Tests
**Duration**: 4-6 hours

- Developer persona: Code-heavy workflow with LSP
- Writer persona: Document editing with search/macros
- Sysadmin persona: Multi-file config editing
- Failure/recovery scenarios (crash, errors, invalid input)

**Commit**: "Phase 3.3: Add end-to-end and persona-based tests"

---

### Sessions 10-11: Polish (Phase 4)
**Duration**: 2-3 days
**Goal**: User experience refinements

1. LSP rename with user prompt
2. Command palette filtering/sorting
3. File finder fuzzy matching
4. Configuration validation
5. Mouse event parsing
6. Tree-sitter enhancements:
   - Syntax-aware text objects (dif = delete inside function)
   - Code folding using tree structure
   - Error node highlighting
7. Signature help automatic triggers ('(' and ',' in insert mode)

**Commit**: "Phase 4: Polish features and UX improvements"

---

### Session 12: Issue Remediation (Phase 5)
**Duration**: 2-3 days
**Goal**: Fix all discovered issues

1. Run full test suite, collect failures
2. Categorize: Critical bugs / Performance / UX / Edge cases
3. Prioritize: P0 (blocks release) / P1 (important) / P2 (nice-to-have)
4. Fix P0 and P1 with regression tests
5. Document P2 in KNOWN_ISSUES.md

**Commit**: "Phase 5: Remediate all P0/P1 issues from testing"

---

### Sessions 13-14: Release Prep (Phase 6)
**Duration**: 2-3 days
**Goal**: Production-ready 0.9 release

#### Security & Quality
- Dependency audit (zio, zigjr, tree-sitter vulnerabilities)
- Code review (JSON parsing, file I/O, terminal sequences)
- Run with AddressSanitizer and UndefinedBehaviorSanitizer
- Basic fuzzing (rope operations, LSP parser)

#### Repository Cleanup
- Remove dead code and stale comments
- Organize docs/ directory structure
- Add CONTRIBUTING.md (code style, PR process, testing requirements)
- Create CHANGELOG.md (0.9 release notes, breaking changes)
- Update .gitignore if needed

#### Documentation
- Update README.md (tree-sitter features, LSP capabilities, screenshots)
- Create LSP.md (supported servers, configuration, troubleshooting)
- Create TESTING.md (running tests, adding tests, coverage targets)
- Create ARCHITECTURE.md (rope, LSP, window manager, rendering, tree-sitter)
- Update existing feature docs for accuracy

#### Release Artifacts
- Create docs/releases/0.9.0.md with detailed release notes
- Tag version: `git tag -a v0.9.0 -m "Aesop 0.9.0 - LSP + Tree-sitter Release"`
- Build binaries for all platforms via CI
- Generate changelog from commits
- Prepare announcement text

**Commits**:
- "Phase 6.1: Security audit and quality improvements"
- "Phase 6.2: Repository cleanup and organization"
- "Phase 6.3: Comprehensive documentation update"
- "Phase 6.4: Prepare 0.9 release artifacts"

---

## Success Criteria

- [ ] **Phase 1**: Critical TODOs resolved ✅
- [ ] **Phase 1B**: LSP enhancements complete ✅
- [ ] **Phase 1C**: Test infrastructure ready
- [ ] **Phase 2**: Tree-sitter fully integrated (5+ languages)
- [ ] **Phase 3**: 70%+ test coverage, all personas validated
- [ ] **Phase 4**: Polish items complete, excellent UX
- [ ] **Phase 5**: All P0/P1 issues resolved
- [ ] **Phase 6**: Security scan clean, docs comprehensive, release tagged

---

## Notes for Continuity

### Build Commands
```bash
# Standard build
zig build

# Run tests
zig build test

# Format code
zig fmt src/

# Check formatting
zig fmt --check src/

# Build release
zig build -Doptimize=ReleaseSafe
```

### Key Files
- `build.zig`: Build configuration
- `build.zig.zon`: Dependencies
- `src/editor/treesitter.zig`: Tree-sitter integration (currently stub)
- `src/lsp/`: LSP client implementation
- `src/render/`: Rendering pipeline
- `docs/TREE_SITTER_INTEGRATION.md`: Detailed tree-sitter plan

### Context Preservation
- All TODOs resolved except event loop integration for signature help
- Diagnostic gutter already implemented and enabled
- LSP stderr logging fully functional
- Tree-sitter roadmap documented in docs/
- Multi-language keyword highlighting working (fallback for tree-sitter)

---

## Estimated Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| 1A-1B (Complete) | 2 days | 2 days ✅ |
| 1C (Test infra) | 1-2 days | 3-4 days |
| 2 (Tree-sitter) | 7-12 days | 10-16 days |
| 3 (Testing) | 3-4 days | 13-20 days |
| 4 (Polish) | 2-3 days | 15-23 days |
| 5 (Issues) | 2-3 days | 17-26 days |
| 6 (Release) | 2-3 days | 19-29 days |

**Total Remaining**: 17-27 days

---

## Getting Help

If you encounter issues during any phase:

1. Check existing docs:
   - `docs/TREE_SITTER_INTEGRATION.md` for tree-sitter details
   - `docs/PROGRESS_PHASE_1.md` for what's been done
   - `docs/architecture/` and `docs/features/` for design decisions

2. Review tests:
   - Look at existing test patterns in source files
   - Use `zig build test` to validate changes

3. Check git history:
   - `git log --oneline` shows recent work
   - `git show <commit>` for detailed changes
   - Recent commits provide implementation patterns

---

## Ready to Continue?

1. Review `docs/PROGRESS_PHASE_1.md` for context
2. Choose next session (recommend Phase 1C first)
3. Create feature branch: `git checkout -b phase-1c-test-infrastructure`
4. Follow session structure above
5. Commit incrementally with descriptive messages
6. Test after each commit: `zig build && zig build test`

**Good luck with Phase 2! Tree-sitter integration is the major remaining architectural work.**
