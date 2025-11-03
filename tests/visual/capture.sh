#!/usr/bin/env bash
# Visual Regression Testing - Screenshot Capture Tool
#
# Captures screenshots of the editor in various states for visual regression testing.
# Screenshots are saved with ANSI escape codes preserved for rich comparison.
#
# Usage:
#   ./capture.sh <test-name> <test-file> [commands...]
#
# Example:
#   ./capture.sh "startup_empty" ""
#   ./capture.sh "edit_zig_file" "test.zig" "i" "const x = 5;" "Escape"

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
AESOP_BINARY="${AESOP_BINARY:-$PROJECT_ROOT/zig-out/bin/aesop}"
TMUX_SESSION="aesop-visual-$$"
SCREENSHOTS_DIR="$PROJECT_ROOT/tests/visual/screenshots"
GOLDEN_DIR="$PROJECT_ROOT/tests/visual/golden"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

die() {
    log_error "$@"
    cleanup
    exit 1
}

cleanup() {
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
}

# Parse arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <test-name> [test-file] [commands...]"
    echo ""
    echo "Captures a screenshot of the editor for visual regression testing."
    echo ""
    echo "Arguments:"
    echo "  test-name    Name for the screenshot (e.g., 'startup_empty')"
    echo "  test-file    Optional file to open (empty string for no file)"
    echo "  commands...  Optional tmux send-keys commands to execute before capture"
    echo ""
    echo "Examples:"
    echo "  $0 startup_empty"
    echo "  $0 edit_zig test.zig i 'const x = 5;' Escape"
    exit 1
fi

TEST_NAME="$1"
shift

TEST_FILE=""
if [[ $# -gt 0 ]]; then
    TEST_FILE="$1"
    shift
fi

COMMANDS=("$@")

# Create directories
mkdir -p "$SCREENSHOTS_DIR"
mkdir -p "$GOLDEN_DIR"

# Check if binary exists
if [[ ! -x "$AESOP_BINARY" ]]; then
    die "Aesop binary not found at: $AESOP_BINARY"
fi

# Check tmux
if ! command -v tmux &> /dev/null; then
    die "tmux not found. Install with: brew install tmux"
fi

log_info "Capturing screenshot: $TEST_NAME"

# Start tmux session
cleanup  # Clean up any existing session

if [[ -n "$TEST_FILE" ]]; then
    # Create test file if it has path separator or use as temp file
    if [[ "$TEST_FILE" == */* ]]; then
        TEST_FILE_PATH="$TEST_FILE"
    else
        TEST_FILE_PATH="/tmp/aesop_visual_$TEST_NAME"
        if [[ ! -f "$TEST_FILE" ]]; then
            # If TEST_FILE doesn't exist, create it
            echo "" > "$TEST_FILE_PATH"
        else
            cp "$TEST_FILE" "$TEST_FILE_PATH"
        fi
    fi

    tmux new-session -d -s "$TMUX_SESSION" -x 80 -y 24 \
        "DYLD_LIBRARY_PATH=~/lib $AESOP_BINARY $TEST_FILE_PATH"
else
    tmux new-session -d -s "$TMUX_SESSION" -x 80 -y 24 \
        "DYLD_LIBRARY_PATH=~/lib $AESOP_BINARY"
fi

# Wait for editor to start
sleep 1

# Execute commands if provided
if [[ ${#COMMANDS[@]} -gt 0 ]]; then
    log_info "Executing ${#COMMANDS[@]} commands..."
    for cmd in "${COMMANDS[@]}"; do
        if [[ "$cmd" == *" "* ]]; then
            # Command contains spaces - use literal mode
            tmux send-keys -t "$TMUX_SESSION" -l "$cmd"
        else
            # Single key or special key
            tmux send-keys -t "$TMUX_SESSION" "$cmd"
        fi
        sleep 0.1
    done

    # Wait for commands to take effect
    sleep 0.5
fi

# Capture screenshot with ANSI escape codes
SCREENSHOT_FILE="$SCREENSHOTS_DIR/${TEST_NAME}.txt"
tmux capture-pane -t "$TMUX_SESSION" -e -p > "$SCREENSHOT_FILE"

log_info "Screenshot saved: $SCREENSHOT_FILE"

# Also capture without escape codes for easier viewing
SCREENSHOT_PLAIN="$SCREENSHOTS_DIR/${TEST_NAME}_plain.txt"
tmux capture-pane -t "$TMUX_SESSION" -p > "$SCREENSHOT_PLAIN"

log_info "Plain screenshot: $SCREENSHOT_PLAIN"

# Display preview
log_info "Preview:"
echo "========================================"
cat "$SCREENSHOT_PLAIN"
echo "========================================"

# Cleanup
cleanup

log_info "Done. Use compare.sh to compare against golden images."
log_info "Use approve.sh to promote this to a golden image."
