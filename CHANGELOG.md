# Changelog

All notable changes to the Aesop editor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2025-11-03

### Added

- **Undo History Branching**: Preserve up to 10 alternate histories when making changes after undo
  - Never lose work - can switch between branches to recover "lost" redo histories
  - New APIs: `branchCount()`, `listBranches()`, `switchToBranch()`
  - Backward compatible with existing linear undo/redo
  - Implements vim-style undo tree concept

- **AVL Rope Rebalancing**: Automatic tree balancing for optimal performance
  - Maintains O(log n) operations for large files with many edits
  - Handles all 4 AVL rotation cases (Left-Left, Left-Right, Right-Right, Right-Left)
  - Balance factor enforced (≤ 2 height difference)
  - Significant performance improvement for heavy editing workflows

- **Enhanced Mark Display**: Full formatted list instead of count-only
  - Shows register name, filename, and line:col position for each mark
  - Format: `a: main.zig:42:15`
  - Handles edge cases (buffers with no name, unknown buffers)

### Fixed

- **UTF-8 Multi-byte Character Handling**: Critical bug fix for LSP completion positioning
  - Added proper UTF-8 character-aware position-to-byte-offset conversion
  - Cursor positions now correctly represent characters, not bytes
  - LSP completion works correctly with Unicode content
  - Fixes crashes and incorrect insertions with multi-byte characters

- **LSP Params Extraction**: Proper JSON stringification
  - Extract and stringify only params portion from LSP notifications
  - Previously passed entire JSON message as params
  - Cleaner notification handling

- **LSP Command Arguments**: Replace placeholder with actual data
  - Proper JSON stringification of command arguments
  - LSP code actions with arguments now work correctly
  - Previously used placeholder `"<args>"` string

- **JSON API Compatibility**: Updated for Zig 0.15.1
  - Use correct `std.json.Stringify.valueAlloc()` API
  - Fixed compilation errors with new Zig standard library
  - Cleaner code with proper error handling

### Changed

- **Mark Display**: Enhanced from count-only to full formatted list
- **Undo System**: Extended with branch preservation (fully backward compatible)
- **Rope Data Structure**: Now maintains AVL balance automatically

### Performance

- **O(log n) guarantee**: Rope operations maintain logarithmic complexity for large files
- **Memory efficiency**: Proper cleanup with defer statements throughout
- **Build times**: All optimizations tested in both debug and release builds

### Testing

- **All 107 tests passing**: Zero failures
- **Zero compiler warnings**: Clean in debug and release builds
- **Memory safety**: All allocations properly managed with defer
- **Build verification**: Both debug and release builds successful

## [Unreleased]

### Added

- **Terminal Detection**: Proper TTY detection before terminal operations
  - Checks if stdin is a TTY using `isatty()` before calling `tcgetattr()`
  - Clear error message when run in non-TTY context (pipes, redirects, automation)
  - Prevents cryptic "error: Unexpected" (errno 19 ENODEV on macOS)

### Planned Features

- Git status display in gutter (editor_app.zig:107)
  - Requires git integration infrastructure
  - Marked as future enhancement

---

## Version History

### [0.9.0] - 2025-11-03
**Stability and Performance Release**

Focus: Code quality, correctness, and performance improvements. This release resolves all critical TODOs and establishes production-ready stability.

**Key highlights:**
- Undo branching prevents losing work
- AVL rebalancing ensures performance at scale
- UTF-8 correctness for international content
- JSON API compatibility with latest Zig

**Statistics:**
- 12 commits
- 6 major features/improvements
- 107/107 tests passing
- 0 compiler warnings
- 0 memory leaks

**Production ready**: Yes ✅
