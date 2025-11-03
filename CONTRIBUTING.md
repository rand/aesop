# Contributing to Aesop

Thank you for your interest in contributing to Aesop! This document provides guidelines for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Testing Requirements](#testing-requirements)
- [Code Style](#code-style)
- [Pull Request Process](#pull-request-process)
- [Bug Reports](#bug-reports)
- [Feature Requests](#feature-requests)

---

## Code of Conduct

- Be respectful and constructive
- Focus on what is best for the community
- Show empathy towards other community members

---

## Getting Started

### Prerequisites

- Zig 0.15.1 or later
- tmux (for E2E tests): `brew install tmux` (macOS) or `apt-get install tmux` (Linux)
- tree-sitter libraries (see docs/BUILDING_WITH_TREE_SITTER.md)

### Clone and Build

```bash
# Clone repository
git clone https://github.com/yourusername/aesop.git
cd aesop

# Build
zig build

# Run tests
zig build test

# Run locally
./zig-out/bin/aesop test_file.zig
```

---

## Development Workflow

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
3. **Make changes** following code style guidelines
4. **Write tests** (see Testing Requirements below)
5. **Run tests** to ensure everything passes
6. **Commit** with clear, descriptive messages
7. **Push** to your fork
8. **Open a Pull Request** against `main`

---

## Testing Requirements

**CRITICAL**: All contributions must include appropriate tests. The v0.9.0/v0.9.1 releases had critical bugs that passed unit tests but made the editor unusable. Our multi-tier testing system prevents this.

### Required Tests

For **every** contribution, you must:

1. **Write unit tests** for new functions/modules
2. **Write integration tests** if crossing module boundaries
3. **Add E2E tests** for new user-facing features
4. **Capture visual tests** if changing UI rendering

### Before Submitting PR

Run the following checks:

```bash
# 1. All tests must pass
zig build test

# 2. E2E smoke tests must pass
./tests/e2e/smoke_test.sh

# 3. Code must be properly formatted
zig fmt src/

# 4. Release build must succeed
zig build -Doptimize=ReleaseSafe
```

### Test Coverage Guidelines

- **Critical paths** (startup, rendering, input): **90%+ coverage required**
- **Core functionality** (editing, saving): **80%+ coverage required**
- **Edge cases**: **70%+ coverage required**

### Writing Tests

See [TESTING.md](TESTING.md) for comprehensive testing guide.

#### Unit Test Example

```zig
test "rope: insert at position" {
    const allocator = std.testing.allocator;
    var rope = try Rope.init(allocator);
    defer rope.deinit();

    try rope.insert(0, "Hello");
    try rope.insert(5, " World");

    const content = try rope.toString(allocator);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("Hello World", content);
}
```

#### Integration Test Example

```zig
test "rendering: status line appears on every render" {
    const allocator = testing.allocator;

    var mock_term = try MockTerminal.init(allocator);
    defer mock_term.deinit();

    var renderer = try Renderer.init(allocator, &mock_term, .{
        .width = 80,
        .height = 24,
    });
    defer renderer.deinit();

    var buffer = try Buffer.init(allocator, "test.zig");
    defer buffer.deinit();

    try renderer.render(buffer, 0, 0);

    try testing.expect(mock_term.hasStatusLine());
}
```

#### E2E Test Example

```bash
test_my_new_feature() {
    log_info "Test: My new feature works"

    local test_file="$TEST_DIR/test.txt"
    echo "content" > "$test_file"

    start_aesop "$test_file"
    sleep 1

    # Test your feature
    send_keys "i"
    send_text "Hello"
    send_keys "Escape"

    assert_screen_contains "Hello" || return 1

    stop_aesop
    return 0
}
```

### Test Quality Checklist

Before submitting, ensure your tests:

- [ ] Have clear, descriptive names
- [ ] Are isolated (no dependencies on other tests)
- [ ] Clean up resources (defer, deinit)
- [ ] Have meaningful assertion messages
- [ ] Would catch the bug/regression they're designed to prevent

---

## Code Style

### Zig Style Guide

Follow the official Zig style guide:

- Use `zig fmt` to format code (enforced in CI)
- Follow standard Zig naming conventions:
  - `camelCase` for functions and variables
  - `PascalCase` for types
  - `SCREAMING_SNAKE_CASE` for constants
- Add doc comments (`///`) for public APIs
- Keep functions focused and reasonably sized

### Example

```zig
/// Insert text into the buffer at the specified position
///
/// Args:
///   position: Byte offset where text should be inserted
///   text: The text to insert
///
/// Returns:
///   Error if position is out of bounds or allocation fails
pub fn insert(self: *Buffer, position: usize, text: []const u8) !void {
    try self.rope.insert(position, text);
    self.modified = true;
}
```

### Error Handling

- Use Zig's error unions (`!T`) for fallible operations
- Provide meaningful error types
- Document what errors a function can return
- Clean up resources on error paths (use `defer` and `errdefer`)

### Memory Management

- Always specify allocator explicitly
- Use `defer` for cleanup
- Use `errdefer` for error-path cleanup
- No memory leaks tolerated (tests will catch them)

---

## Pull Request Process

### PR Checklist

Before submitting your PR, ensure:

- [ ] All tests pass (`zig build test`)
- [ ] E2E smoke tests pass (`./tests/e2e/smoke_test.sh`)
- [ ] Code is formatted (`zig fmt src/`)
- [ ] New tests added for new functionality
- [ ] Documentation updated (if API changes)
- [ ] CHANGELOG.md updated (for notable changes)
- [ ] Commit messages are clear and descriptive

### PR Template

When opening a PR, include:

1. **Description**: What does this PR do?
2. **Motivation**: Why is this change needed?
3. **Testing**: What tests were added? (link to test files)
4. **Screenshots**: If UI changes, include before/after screenshots
5. **Breaking Changes**: List any breaking changes
6. **Related Issues**: Link to related issues (Fixes #123)

### Example PR Description

```markdown
## Description
Add support for multi-cursor editing

## Motivation
Multi-cursor editing is a highly requested feature that improves
productivity when making repetitive edits.

## Testing
- Added unit tests: `src/editor/multi_cursor.zig` (test blocks)
- Added integration tests: `tests/integration/multi_cursor_test.zig`
- Added E2E test: `tests/e2e/workflow_test.sh` (test_multi_cursor_workflow)

## Screenshots
[Visual demonstration of multi-cursor editing]

## Breaking Changes
None

## Related Issues
Fixes #42
```

### Review Process

1. PR submitted → Automated CI runs all tests
2. Maintainer reviews code and tests
3. Feedback provided (if needed)
4. Changes addressed
5. PR approved and merged

---

## Bug Reports

### Before Submitting

1. Check if the bug is already reported in Issues
2. Try to reproduce with latest `main` branch
3. Gather information about your environment

### Bug Report Template

```markdown
## Description
[Clear description of the bug]

## Steps to Reproduce
1. Open aesop with `./aesop test.zig`
2. Press 'i' to enter insert mode
3. Type "hello"
4. [Bug occurs here]

## Expected Behavior
[What you expected to happen]

## Actual Behavior
[What actually happened]

## Environment
- OS: macOS 14.0 / Ubuntu 22.04 / Windows 11
- Zig version: 0.15.1
- Aesop version/commit: ae5e975

## Additional Context
[Screenshots, logs, etc.]
```

---

## Feature Requests

### Feature Request Template

```markdown
## Feature Description
[Clear description of the proposed feature]

## Use Case
[Why is this feature needed? What problem does it solve?]

## Proposed Implementation
[Optional: How would you implement this?]

## Alternatives Considered
[Optional: Other approaches you've thought about]
```

---

## Development Tips

### Running Individual Tests

```bash
# Run single unit test file
zig test src/buffer/rope.zig

# Run only integration tests
zig build test-integration

# Run single E2E test
source tests/e2e/harness.sh
setup
test_editor_opens_with_content
cleanup
```

### Debugging

```bash
# Build with debug symbols
zig build

# Run with debug output
./zig-out/bin/aesop --debug test.zig

# Use GDB/LLDB
lldb ./zig-out/bin/aesop
```

### Common Issues

**Issue**: "tree-sitter library not found"

**Solution**: Install tree-sitter and grammars (see docs/BUILDING_WITH_TREE_SITTER.md)

**Issue**: "E2E tests fail with tmux error"

**Solution**: Install tmux (`brew install tmux` or `apt-get install tmux`)

**Issue**: "Tests pass locally but fail in CI"

**Solution**: Ensure your changes work on all platforms (Linux, macOS, Windows)

---

## Questions?

- Open a Discussion on GitHub
- Check existing Issues and PRs
- Read the documentation in `docs/`
- Review the testing guide in [TESTING.md](TESTING.md)

---

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see LICENSE file).

---

## Thank You!

Your contributions make Aesop better for everyone. Thank you for taking the time to contribute!
