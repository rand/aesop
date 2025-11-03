# Next Session: Test Infrastructure Enhancement Plan

## Context
Previous session fixed critical bugs and validated test infrastructure. This session will implement missing features to achieve 100% E2E test pass rate.

## Current State
- ✅ E2E smoke tests: 4/4 passing
- ⚠️ E2E workflow tests: 3/5 passing
- ❌ Unit/Integration: Blocked by tree-sitter

## 5-Phase Enhancement Plan

### PHASE 1: Implement Command Mode (~45 min) 🎯 START HERE
**Goal**: Enable `:q`, `:w`, `:wq` commands

**Tasks**:
1. Create `src/editor/commandline.zig` - command parser
2. Wire command mode in `src/editor_app.zig` - capture `:` input
3. Bind `:` key in normal mode
4. Update `tests/e2e/smoke_test.sh` - un-skip quit test

**Success**: `:q` closes editor, E2E smoke 4/4 (no skips)

---

### PHASE 2: Fix Search Workflow (~30 min)
**Goal**: Enable `/` search and `n` next-match

**Investigation**: Check `src/editor/search.zig` - what exists?

**Tasks**:
- Bind `/` to enter search mode
- Implement forward search in buffer
- Connect `n` to next match
- Update status line for search mode

**Success**: E2E search workflow test passes

---

### PHASE 3: Fix Undo/Redo (~30 min)
**Goal**: Make `u` and `Ctrl+R` work

**Investigation**: Check `src/editor/undo.zig` - is it wired?

**Tasks**:
- Ensure edits record to undo stack
- Bind `u` to undo
- Bind `Ctrl+R` to redo
- Fix operation application if broken

**Success**: E2E undo/redo workflow test passes

---

### PHASE 4: Conditional Tree-Sitter (~45 min)
**Goal**: Make tree-sitter optional

**Tasks**:
1. Add build option in `build.zig`: `-Denable-treesitter`
2. Wrap all `linkSystemLibrary` calls conditionally
3. Add `build_options` to code
4. Create stub/mock when disabled

**Success**: `zig build test -Denable-treesitter=false` runs

---

### PHASE 5: Mock Tree-Sitter for CI (~30 min)
**Goal**: Stub implementation for tests

**Tasks**:
1. Create `src/treesitter/mock_bindings.zig`
2. Conditional import in bindings
3. Update `.github/workflows/ci.yml`

**Success**: CI runs full test suite

---

## Execution Order
1. **Phase 1** (highest value, enables full E2E smoke)
2. **Phases 2-3** (can be parallel, enables full E2E workflow)
3. **Phase 4** (prerequisite for Phase 5)
4. **Phase 5** (enables CI automation)

## Time Estimate
~3 hours total for all 5 phases

## Files to Reference
- `TEST_SESSION_SUMMARY.md` - Previous session results
- `TESTING.md` - Current test status
- `tests/e2e/workflow_test.sh` - Test requirements

## Success Metrics
- E2E smoke: 4/4 (no skips)
- E2E workflow: 5/5 
- Unit tests: Runnable
- Integration tests: Runnable
- CI: Automated

## Start Point
Begin with Phase 1, Task 1: Create command line parser.
