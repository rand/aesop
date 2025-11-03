#!/usr/bin/env bash
# E2E Test Harness for Aesop Editor
#
# Uses tmux to provide a real pseudo-TTY environment for testing
# the actual binary as a user would run it.
#
# This harness would have caught the v0.9.0/v0.9.1 bugs:
# - Blank screen on first render
# - Text staircase effect
# - Input lag and missed keypresses

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AESOP_BINARY="${AESOP_BINARY:-./zig-out/bin/aesop}"
TMUX_SESSION="aesop-e2e-test-$$"
TMUX_WINDOW="test-window"
TEST_DIR="${TEST_DIR:-/tmp/aesop-test-$$}"
SCREENSHOT_DIR="${TEST_DIR}/screenshots"

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#############################################################################
# Helper Functions
#############################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

die() {
    log_error "$@"
    cleanup
    exit 1
}

# Setup test environment
setup() {
    log_info "Setting up E2E test environment..."

    # Check if aesop binary exists
    if [[ ! -x "$AESOP_BINARY" ]]; then
        die "Aesop binary not found at: $AESOP_BINARY"
    fi

    # Check if tmux is available
    if ! command -v tmux &> /dev/null; then
        die "tmux not found. Install with: brew install tmux (macOS) or apt-get install tmux (Linux)"
    fi

    # Create test directory
    mkdir -p "$TEST_DIR"
    mkdir -p "$SCREENSHOT_DIR"

    log_info "Test directory: $TEST_DIR"
    log_info "Aesop binary: $AESOP_BINARY"
}

# Cleanup test environment
cleanup() {
    log_info "Cleaning up..."

    # Kill tmux session if it exists
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$TMUX_SESSION"
    fi

    # Clean up test directory (optional - keep for debugging)
    # rm -rf "$TEST_DIR"

    log_info "Cleanup complete. Test artifacts in: $TEST_DIR"
}

# Start aesop in tmux session
start_aesop() {
    local test_file="${1:-}"

    log_info "Starting aesop in tmux session..."

    # Kill existing session if any
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

    # Create new session (detached)
    if [[ -n "$test_file" ]]; then
        tmux new-session -d -s "$TMUX_SESSION" -n "$TMUX_WINDOW" \
            "DYLD_LIBRARY_PATH=~/lib $AESOP_BINARY $test_file"
    else
        tmux new-session -d -s "$TMUX_SESSION" -n "$TMUX_WINDOW" \
            "DYLD_LIBRARY_PATH=~/lib $AESOP_BINARY"
    fi

    # Give editor time to initialize
    sleep 0.5
}

# Stop aesop
stop_aesop() {
    log_info "Stopping aesop..."

    # Send quit command (ESC :q ENTER)
    send_keys "Escape"
    sleep 0.1
    send_keys ":" "q" "Enter"
    sleep 0.2

    # Force kill if still running
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
}

# Send keys to tmux session
send_keys() {
    for key in "$@"; do
        tmux send-keys -t "$TMUX_SESSION:$TMUX_WINDOW" "$key"
        sleep 0.05  # Small delay between keys
    done
}

# Send literal text (not special keys)
send_text() {
    local text="$1"
    tmux send-keys -t "$TMUX_SESSION:$TMUX_WINDOW" -l "$text"
    sleep 0.1
}

# Capture screen content
capture_screen() {
    local output_file="${1:-$TEST_DIR/screen.txt}"
    tmux capture-pane -t "$TMUX_SESSION:$TMUX_WINDOW" -p > "$output_file"
    echo "$output_file"
}

# Capture screen as screenshot (using ANSI escape codes)
capture_screenshot() {
    local name="${1:-screenshot}"
    local output_file="$SCREENSHOT_DIR/${name}.txt"
    tmux capture-pane -t "$TMUX_SESSION:$TMUX_WINDOW" -e -p > "$output_file"
    echo "$output_file"
}

# Wait for text to appear on screen
wait_for_text() {
    local text="$1"
    local timeout="${2:-5}"
    local start_time=$(date +%s)

    while true; do
        local screen_file=$(capture_screen "$TEST_DIR/wait_check.txt")
        if grep -q "$text" "$screen_file"; then
            return 0
        fi

        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for text: $text"
            return 1
        fi

        sleep 0.2
    done
}

# Check if screen contains text
screen_contains() {
    local text="$1"
    local screen_file=$(capture_screen "$TEST_DIR/check.txt")
    if grep -q "$text" "$screen_file"; then
        return 0
    else
        return 1
    fi
}

# Check if screen is NOT blank
screen_has_content() {
    local screen_file=$(capture_screen "$TEST_DIR/content_check.txt")
    # Check if there's any non-whitespace content
    if grep -q '[^[:space:]]' "$screen_file"; then
        return 0
    else
        log_error "Screen is blank!"
        cat "$screen_file"
        return 1
    fi
}

# Assert that screen contains text
assert_screen_contains() {
    local text="$1"
    local message="${2:-Screen should contain: $text}"

    if screen_contains "$text"; then
        log_info "✓ $message"
        return 0
    else
        log_error "✗ $message"
        log_error "Screen content:"
        cat "$TEST_DIR/check.txt"
        return 1
    fi
}

# Assert that screen has visible content
assert_screen_has_content() {
    local message="${1:-Screen should have visible content}"

    if screen_has_content; then
        log_info "✓ $message"
        return 0
    else
        log_error "✗ $message"
        return 1
    fi
}

#############################################################################
# Test Framework
#############################################################################

run_test() {
    local test_name="$1"
    local test_function="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    log_info ""
    log_info "========================================="
    log_info "Running test: $test_name"
    log_info "========================================="

    if $test_function; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_info "${GREEN}✓ PASSED${NC}: $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "${RED}✗ FAILED${NC}: $test_name"
    fi
}

print_summary() {
    log_info ""
    log_info "========================================="
    log_info "Test Summary"
    log_info "========================================="
    log_info "Tests run:    $TESTS_RUN"
    log_info "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    log_info "Tests failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "${GREEN}All tests passed!${NC}"
        return 0
    else
        log_error "${RED}Some tests failed!${NC}"
        return 1
    fi
}

#############################################################################
# Export functions for use in test scripts
#############################################################################

export -f log_info log_error log_warn die
export -f setup cleanup
export -f start_aesop stop_aesop
export -f send_keys send_text
export -f capture_screen capture_screenshot
export -f wait_for_text screen_contains screen_has_content
export -f assert_screen_contains assert_screen_has_content
export -f run_test print_summary

# If sourced, don't run anything
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "E2E Test Harness - use 'source harness.sh' to import functions"
    log_info "Or run individual test scripts that source this file"
fi
