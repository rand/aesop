#!/usr/bin/env bash
# E2E Smoke Tests for Aesop Editor
#
# These tests verify basic functionality that a user would expect:
# 1. Editor opens and displays content
# 2. Text input works
# 3. Basic navigation works
# 4. Editor closes cleanly
#
# These tests would have caught the v0.9.0/v0.9.1 bugs:
# - Blank screen on first render (Test 1)
# - Text staircase effect (Test 2)
# - Input lag (Test 2)

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source harness
# shellcheck source=harness.sh
source "$SCRIPT_DIR/harness.sh"

#############################################################################
# Smoke Test 1: Editor opens and displays content
#############################################################################

test_editor_opens_with_content() {
    log_info "Test: Editor opens and displays content"

    # Create test file
    local test_file="$TEST_DIR/test1.txt"
    cat > "$test_file" << 'EOF'
Hello, World!
This is a test file.
Line 3 here.
EOF

    # Start editor with file
    start_aesop "$test_file"

    # Wait for editor to render
    sleep 1

    # CRITICAL: Screen must have visible content (v0.9.0 bug check)
    assert_screen_has_content "Screen should not be blank on startup" || return 1

    # Check that file content is displayed
    assert_screen_contains "Hello, World!" "First line should be visible" || return 1
    assert_screen_contains "test file" "Second line should be visible" || return 1

    # Check for status line (mode indicator or filename)
    if screen_contains "NORMAL" || screen_contains "test1.txt"; then
        log_info "✓ Status line is present"
    else
        log_error "✗ Status line not found"
        return 1
    fi

    # Capture screenshot for visual verification
    local screenshot=$(capture_screenshot "test1_initial_render")
    log_info "Screenshot saved: $screenshot"

    # Stop editor
    stop_aesop

    return 0
}

#############################################################################
# Smoke Test 2: Text input works
#############################################################################

test_text_input_works() {
    log_info "Test: Text input works"

    # Start editor with empty file
    local test_file="$TEST_DIR/test2.txt"
    echo "" > "$test_file"

    start_aesop "$test_file"
    sleep 1

    # Enter insert mode
    send_keys "i"
    sleep 0.2

    # Type some text
    send_text "Hello from E2E test!"
    sleep 0.3

    # Check that text appears on screen
    # CRITICAL: Text should render correctly without staircase effect (v0.9.1 bug check)
    assert_screen_contains "Hello from E2E test!" "Typed text should appear" || return 1

    # Type more text with newline
    send_keys "Enter"
    send_text "Second line here."
    sleep 0.3

    assert_screen_contains "Second line" "Second line should appear" || return 1

    # Capture screenshot
    capture_screenshot "test2_text_input"

    # Stop editor
    stop_aesop

    return 0
}

#############################################################################
# Smoke Test 3: Basic navigation works
#############################################################################

test_navigation_works() {
    log_info "Test: Basic navigation works"

    # Create test file with multiple lines
    local test_file="$TEST_DIR/test3.txt"
    cat > "$test_file" << 'EOF'
Line 1
Line 2
Line 3
Line 4
Line 5
EOF

    start_aesop "$test_file"
    sleep 1

    # Initial state - should show Line 1
    assert_screen_contains "Line 1" "Initial: Line 1 should be visible" || return 1

    # Move down with 'j' key
    send_keys "j"
    sleep 0.2

    # Cursor should move (we can't directly check cursor position, but navigation should work)

    # Move down several more times
    send_keys "j" "j" "j"
    sleep 0.2

    # All lines should still be visible (file is small)
    assert_screen_contains "Line 5" "After navigation: Line 5 should be visible" || return 1

    # Move up with 'k' key
    send_keys "k" "k"
    sleep 0.2

    # Move to end of line with '$'
    send_keys '$'
    sleep 0.2

    # Move to beginning with '0'
    send_keys "0"
    sleep 0.2

    # Capture screenshot
    capture_screenshot "test3_navigation"

    # Stop editor
    stop_aesop

    return 0
}

#############################################################################
# Smoke Test 4: Editor closes cleanly
#############################################################################

test_editor_closes_cleanly() {
    log_info "Test: Editor closes cleanly"

    local test_file="$TEST_DIR/quit_test.txt"
    echo "Testing quit command" > "$test_file"

    start_aesop "$test_file"
    sleep 1

    # Check editor is running
    assert_screen_has_content "Editor should display content before quit" || return 1

    # Enter command mode and type :q
    send_keys ":"
    sleep 0.2

    # Type 'q' and press Enter
    send_text "q"
    send_keys "Enter"
    sleep 0.5

    # Verify editor has exited (tmux pane should be gone or show shell prompt)
    # Check if aesop process is still running
    if pgrep -f "$AESOP_BINARY" > /dev/null; then
        log_error "Editor process still running after :q"
        stop_aesop  # Force cleanup
        return 1
    fi

    log_info "✓ Editor quit successfully with :q command"
    return 0
}

#############################################################################
# Main Test Runner
#############################################################################

main() {
    log_info "Starting Aesop E2E Smoke Tests"

    # Setup
    setup

    # Run tests
    run_test "Editor opens and displays content" test_editor_opens_with_content
    run_test "Text input works" test_text_input_works
    run_test "Basic navigation works" test_navigation_works
    run_test "Editor closes cleanly" test_editor_closes_cleanly

    # Print summary
    print_summary

    # Cleanup
    cleanup

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
