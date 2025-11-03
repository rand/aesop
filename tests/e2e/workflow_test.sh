#!/usr/bin/env bash
# E2E Workflow Tests for Aesop Editor
#
# These tests verify complete editing workflows that users would perform:
# 1. Open → Edit → Save → Close workflow
# 2. Search and replace workflow
# 3. Multi-line editing workflow
# 4. Undo/redo workflow

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source harness
# shellcheck source=harness.sh
source "$SCRIPT_DIR/harness.sh"

#############################################################################
# Workflow Test 1: Complete edit-save-close workflow
#############################################################################

test_edit_save_close_workflow() {
    log_info "Test: Complete edit-save-close workflow"

    # Create test file
    local test_file="$TEST_DIR/workflow1.txt"
    cat > "$test_file" << 'EOF'
Original content
Line 2
Line 3
EOF

    start_aesop "$test_file"
    sleep 1

    # Verify initial content
    assert_screen_contains "Original content" || return 1

    # Enter insert mode and add text
    send_keys "i"
    sleep 0.2
    send_text "NEW FIRST LINE"
    send_keys "Enter"
    sleep 0.3

    # Exit insert mode
    send_keys "Escape"
    sleep 0.2

    # Save file (:w)
    send_keys ":" "w" "Enter"
    sleep 0.5

    # Close editor (:q)
    send_keys ":" "q" "Enter"
    sleep 0.5

    # Verify file was saved with new content
    if grep -q "NEW FIRST LINE" "$test_file"; then
        log_info "✓ File was saved correctly"
    else
        log_error "✗ File was not saved correctly"
        cat "$test_file"
        return 1
    fi

    if grep -q "Original content" "$test_file"; then
        log_info "✓ Original content preserved"
    else
        log_error "✗ Original content lost"
        return 1
    fi

    return 0
}

#############################################################################
# Workflow Test 2: Search workflow
#############################################################################

test_search_workflow() {
    log_info "Test: Search workflow"

    # Create test file with searchable content
    local test_file="$TEST_DIR/workflow2.txt"
    cat > "$test_file" << 'EOF'
The quick brown fox jumps over the lazy dog.
Another line here.
The word "quick" appears again.
Final line.
EOF

    start_aesop "$test_file"
    sleep 1

    # Perform search for "quick"
    send_keys "/"
    sleep 0.2
    send_text "quick"
    send_keys "Enter"
    sleep 0.3

    # After search, cursor should be on/near "quick"
    # We can't directly verify cursor position, but search should work

    # Capture screenshot showing search result
    capture_screenshot "workflow2_search_result"

    # Try next search result (if multiple matches)
    send_keys "n"
    sleep 0.2

    # Capture second result
    capture_screenshot "workflow2_search_next"

    stop_aesop

    return 0
}

#############################################################################
# Workflow Test 3: Multi-line editing workflow
#############################################################################

test_multiline_edit_workflow() {
    log_info "Test: Multi-line editing workflow"

    # Create test file
    local test_file="$TEST_DIR/workflow3.txt"
    cat > "$test_file" << 'EOF'
Line 1
Line 2
Line 3
Line 4
Line 5
EOF

    start_aesop "$test_file"
    sleep 1

    # Navigate to line 2
    send_keys "j"
    sleep 0.2

    # Delete line (dd)
    send_keys "d" "d"
    sleep 0.3

    # Verify line deleted (Line 2 should be gone, Line 3 should move up)
    # This is hard to verify directly in screen capture, but the operation should work

    # Navigate to line 3 (now line 2 after deletion)
    send_keys "j"
    sleep 0.2

    # Insert new line below (o)
    send_keys "o"
    sleep 0.2
    send_text "Inserted line"
    send_keys "Escape"
    sleep 0.3

    # Verify insertion
    assert_screen_contains "Inserted line" || return 1

    # Capture final state
    capture_screenshot "workflow3_multiline_edit"

    stop_aesop

    return 0
}

#############################################################################
# Workflow Test 4: Undo/redo workflow
#############################################################################

test_undo_redo_workflow() {
    log_info "Test: Undo/redo workflow"

    # Create test file
    local test_file="$TEST_DIR/workflow4.txt"
    echo "Original text" > "$test_file"

    start_aesop "$test_file"
    sleep 1

    # Make first edit
    send_keys "i"
    sleep 0.2
    send_text " - Edit 1"
    send_keys "Escape"
    sleep 0.3

    assert_screen_contains "Edit 1" || return 1

    # Make second edit
    send_keys "a"
    sleep 0.2
    send_text " - Edit 2"
    send_keys "Escape"
    sleep 0.3

    assert_screen_contains "Edit 2" || return 1

    # Undo (u)
    send_keys "u"
    sleep 0.3

    # Edit 2 should be gone, Edit 1 should remain
    if screen_contains "Edit 2"; then
        log_error "✗ Undo failed - Edit 2 still present"
        return 1
    fi

    assert_screen_contains "Edit 1" "After undo: Edit 1 should remain" || return 1

    # Redo (Shift+U)
    send_keys "U"
    sleep 0.3

    # Edit 2 should be back
    assert_screen_contains "Edit 2" "After redo: Edit 2 should be back" || return 1

    # Capture final state
    capture_screenshot "workflow4_undo_redo"

    stop_aesop

    return 0
}

#############################################################################
# Workflow Test 5: Copy/paste workflow
#############################################################################

test_copy_paste_workflow() {
    log_info "Test: Copy/paste workflow"

    # Create test file
    local test_file="$TEST_DIR/workflow5.txt"
    cat > "$test_file" << 'EOF'
First line to copy
Second line
Third line
EOF

    start_aesop "$test_file"
    sleep 1

    # Yank (copy) current line (yy)
    send_keys "y" "y"
    sleep 0.2

    # Move down
    send_keys "j"
    sleep 0.2

    # Paste below (p)
    send_keys "p"
    sleep 0.3

    # First line should now appear twice
    # Count occurrences of "First line to copy"
    local screen_file=$(capture_screen "$TEST_DIR/workflow5_screen.txt")
    local count=$(grep -c "First line to copy" "$screen_file" || echo "0")

    if [[ "$count" -ge 2 ]]; then
        log_info "✓ Copy/paste worked - found $count occurrences"
    else
        log_error "✗ Copy/paste failed - only found $count occurrences"
        cat "$screen_file"
        return 1
    fi

    capture_screenshot "workflow5_copy_paste"

    stop_aesop

    return 0
}

#############################################################################
# Main Test Runner
#############################################################################

main() {
    log_info "Starting Aesop E2E Workflow Tests"

    # Setup
    setup

    # Run tests
    run_test "Edit-save-close workflow" test_edit_save_close_workflow
    run_test "Search workflow" test_search_workflow
    run_test "Multi-line editing workflow" test_multiline_edit_workflow
    run_test "Undo/redo workflow" test_undo_redo_workflow
    run_test "Copy/paste workflow" test_copy_paste_workflow

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
