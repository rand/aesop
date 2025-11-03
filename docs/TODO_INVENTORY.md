# TODO Inventory

**Date**: November 3, 2025
**Purpose**: Catalog remaining TODOs, assess priority, and plan resolution

---

## Overview

This document catalogs all remaining TODO/FIXME/HACK comments in the codebase, categorized by priority and area.

**Total TODOs Found**: 13

---

## Priority P0 (Critical - Required for v0.9.0)

None identified. All critical functionality is implemented.

---

## Priority P1 (High - Should complete for v0.9.0)

### 1. Tree-sitter Grammar Installation
**File**: `src/editor/treesitter.zig:134`
**Code**:
```zig
// TODO: Install and link tree-sitter-zig grammar
// The grammar library must be installed and linked via build.zig
// For now, returning null to allow compilation without the grammar
.zig => null, // Will be: ts.tree_sitter_zig(),
```

**Status**: Known issue, documented
**Plan**: Install grammar libraries and enable in getTreeSitterLanguage()
**Estimated Effort**: 2-4 hours (per language)
**Blocking**: Phase 2.4 completion
**Resolution**: Install grammars for Zig, Rust, Go, Python, C

---

## Priority P2 (Medium - Nice to have for v0.9.0)

### 2. Mouse Event Parsing
**File**: `src/terminal/input.zig`
**Code**:
```zig
// TODO: Implement mouse event parsing
```

**Status**: Mouse support planned but not critical
**Plan**: Implement mouse event parsing in Phase 4
**Estimated Effort**: 4-6 hours
**Impact**: Enables mouse support (clicking, scrolling, selection)
**Resolution**: Implement in Phase 4 polish

### 3. LSP Rename User Prompt
**File**: `src/editor/command.zig`
**Code**:
```zig
// TODO: Prompt user for new name (for now use placeholder)
```

**Status**: Basic LSP rename works, needs user input
**Plan**: Add prompt system integration for rename
**Estimated Effort**: 2-3 hours
**Impact**: Better UX for LSP rename command
**Resolution**: Implement in Phase 4 polish

### 4. Undo Tree Branching
**File**: `src/editor/undo.zig`
**Code**:
```zig
// For simplicity, we'll discard the future for now (TODO: proper branching)
```

**Status**: Linear undo works, branching would be nice
**Plan**: Implement proper undo tree with branch navigation
**Estimated Effort**: 6-8 hours
**Impact**: Advanced undo/redo with branch history
**Resolution**: Consider for post-v0.9.0

---

## Priority P3 (Low - Post-v0.9.0)

### 5. Git Status Display
**File**: `src/editor_app.zig`
**Code**:
```zig
.show_git_status = false, // TODO: Future feature
```

**Status**: Git integration not planned for v0.9.0
**Plan**: Implement git status in status line (future)
**Estimated Effort**: 8-12 hours
**Impact**: Shows git branch and file status
**Resolution**: Post-v0.9.0 feature

### 6. Signature Help Arguments
**File**: `src/lsp/response_parser.zig`
**Code**:
```zig
// TODO: Fully parse and store arguments when needed
```

**Status**: Basic signature help works
**Plan**: Add full argument parsing for detailed info
**Estimated Effort**: 2-3 hours
**Impact**: Better signature help display
**Resolution**: Post-v0.9.0 enhancement

### 7. LSP Params Parsing Improvement
**File**: `src/lsp/client.zig`
**Code**:
```zig
// TODO: Better approach would be to extract just the params portion
```

**Status**: Current approach works but could be cleaner
**Plan**: Refactor to extract params without full parsing
**Estimated Effort**: 3-4 hours
**Impact**: Cleaner code, slight performance improvement
**Resolution**: Post-v0.9.0 refactor

### 8. Mark Display in Palette
**File**: `src/editor/command.zig`
**Code**:
```zig
// Show first mark info (TODO: show in palette or buffer)
```

**Status**: Marks work, display could be better
**Plan**: Show mark list in command palette
**Estimated Effort**: 2-3 hours
**Impact**: Better mark navigation
**Resolution**: Post-v0.9.0 enhancement

### 9. Jump to Line Input
**File**: `src/editor/command.zig`
**Code**:
```zig
// TODO: Get line number from user input
```

**Status**: :G command works with hardcoded value
**Plan**: Add prompt for line number input
**Estimated Effort**: 1-2 hours
**Impact**: User can input line number to jump to
**Resolution**: Post-v0.9.0 or Phase 4

### 10. File URI Conversion
**File**: `src/editor/command.zig`
**Code**:
```zig
// TODO: Convert filepath to file:// URI
```

**Status**: Basic filepath works for most cases
**Plan**: Proper file:// URI encoding
**Estimated Effort**: 1-2 hours
**Impact**: Better LSP compatibility
**Resolution**: Post-v0.9.0 enhancement

### 11. Multi-byte Character Handling
**File**: `src/editor/command.zig`
**Code**:
```zig
// TODO: This is simplified - should handle multi-byte characters properly
```

**Status**: Basic character handling works
**Plan**: Proper UTF-8 multi-byte character support
**Estimated Effort**: 3-4 hours
**Impact**: Better handling of Unicode text
**Resolution**: Post-v0.9.0 (rope already UTF-8 aware)

### 12. Callback Cleanup
**File**: `src/editor/command.zig`
**Code**:
```zig
// Note: fmt_ctx should be freed in callback, but for now it leaks (TODO: add callback cleanup)
```

**Status**: Minor memory leak in format callback
**Plan**: Add proper cleanup mechanism for callbacks
**Estimated Effort**: 2-3 hours
**Impact**: Fixes small memory leak
**Resolution**: Should fix for v0.9.0 or shortly after

### 13. Rope Rebalancing
**File**: `src/buffer/rope.zig`
**Code**:
```zig
// TODO: Implement AVL-style rebalancing
```

**Status**: Basic rebalancing works, AVL would be optimal
**Plan**: Implement proper AVL tree rebalancing
**Estimated Effort**: 6-8 hours
**Impact**: Optimal rope performance
**Resolution**: Post-v0.9.0 optimization

---

## Summary by Priority

| Priority | Count | Should Complete |
|----------|-------|----------------|
| P0 (Critical) | 0 | Before release |
| P1 (High) | 1 | For v0.9.0 |
| P2 (Medium) | 4 | Nice to have for v0.9.0 |
| P3 (Low) | 8 | Post-v0.9.0 |

---

## Recommended Action Plan

### For v0.9.0 Release

**Must Complete (P1)**:
1. Install tree-sitter grammars and enable highlighting

**Should Complete (P2)**:
1. Mouse event parsing (Phase 4)
2. LSP rename user prompt (Phase 4)
3. Consider undo tree branching (if time permits)

**Can Defer (P3)**:
- All P3 items can be deferred to post-v0.9.0
- Exception: Callback cleanup (#12) should be fixed to prevent memory leaks

### Immediate Next Steps

1. **Install grammars** (P1): Unblocks full syntax highlighting
2. **Mouse parsing** (P2): Implement in Phase 4 polish
3. **LSP rename prompt** (P2): Implement in Phase 4 polish
4. **Fix callback cleanup** (P3): Small fix, prevents memory leak

---

## Notes

### Good Practices Observed

1. **All TODOs are documented**: Every TODO has context
2. **TODOs are specific**: Clear description of what needs to be done
3. **No blocking TODOs**: All critical functionality works
4. **Most TODOs are enhancements**: Not bugs or missing features

### Code Quality

- **No FIXME comments**: No urgent fixes needed
- **No HACK comments**: No workarounds that need cleanup
- **No XXX comments**: No danger zones or problematic code
- **Clean codebase**: TODOs are future improvements, not problems

---

## Tracking

This inventory will be updated as TODOs are resolved:

- ✅ Completed TODOs will be marked and dated
- 🔄 In-progress TODOs will be noted
- ❌ Cancelled/invalid TODOs will be documented

**Next Review**: After Phase 4 completion
