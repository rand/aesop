#!/usr/bin/env bash
# Visual Regression Testing - Screenshot Approval Tool
#
# Promotes a screenshot to become a golden image (reference image).
# Use this when:
# 1. Creating a new visual test for the first time
# 2. Intentionally changing visual appearance and updating the baseline
#
# Usage:
#   ./approve.sh <test-name>       # Approve single test
#   ./approve.sh --all             # Approve all tests

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# Statistics
APPROVED_COUNT=0
SKIPPED_COUNT=0

# Create golden directory
mkdir -p "$GOLDEN_DIR"

# Approve single screenshot
approve_screenshot() {
    local test_name="$1"
    local screenshot="$SCREENSHOTS_DIR/${test_name}.txt"
    local golden="$GOLDEN_DIR/${test_name}.txt"

    if [[ ! -f "$screenshot" ]]; then
        log_error "Screenshot not found: $screenshot"
        log_error "Run: ./capture.sh $test_name"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 1
    fi

    # Check if golden already exists
    if [[ -f "$golden" ]]; then
        log_warn "Golden image already exists: $golden"

        # Show diff if different
        if ! diff -q "$golden" "$screenshot" > /dev/null 2>&1; then
            log_warn "Current golden differs from new screenshot"
            log_warn "Showing diff (first 20 lines):"
            diff -u "$golden" "$screenshot" | head -20 || true

            # Ask for confirmation
            read -r -p "Overwrite golden image? [y/N] " response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log_info "Skipped: $test_name"
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                return 1
            fi
        else
            log_info "Golden image is already up to date: $test_name"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        fi
    fi

    # Copy screenshot to golden
    cp "$screenshot" "$golden"
    log_info "✓ Approved: $test_name"
    log_info "  Golden image: $golden"

    APPROVED_COUNT=$((APPROVED_COUNT + 1))
    return 0
}

# Approve all screenshots
approve_all() {
    log_info "Approving all screenshots as golden images..."

    if [[ ! -d "$SCREENSHOTS_DIR" ]] || [[ -z "$(ls -A "$SCREENSHOTS_DIR" 2>/dev/null)" ]]; then
        log_error "No screenshots found in: $SCREENSHOTS_DIR"
        log_error "Run capture.sh to create screenshots first"
        exit 1
    fi

    # Ask for confirmation for batch approval
    log_warn "This will approve all screenshots as golden images."
    log_warn "Existing golden images will be OVERWRITTEN."
    read -r -p "Continue? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        exit 0
    fi

    for screenshot in "$SCREENSHOTS_DIR"/*.txt; do
        # Skip plain versions
        if [[ "$screenshot" == *"_plain.txt" ]]; then
            continue
        fi

        local basename=$(basename "$screenshot" .txt)

        # Copy without asking for individual confirmation
        local golden="$GOLDEN_DIR/${basename}.txt"
        cp "$screenshot" "$golden"
        log_info "✓ Approved: $basename"
        APPROVED_COUNT=$((APPROVED_COUNT + 1))
    done
}

# Print summary
print_summary() {
    echo ""
    log_info "========================================="
    log_info "Approval Summary"
    log_info "========================================="
    log_info "Approved: ${GREEN}$APPROVED_COUNT${NC}"
    log_info "Skipped:  ${YELLOW}$SKIPPED_COUNT${NC}"

    if [[ $APPROVED_COUNT -gt 0 ]]; then
        log_info "${GREEN}✓ Golden images updated${NC}"
        log_info "Golden images are stored in: $GOLDEN_DIR"
        log_info "Commit these to version control to track visual changes"
    fi
}

# Main
main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <test-name> | --all"
        echo ""
        echo "Approve a screenshot as a golden image for visual regression testing."
        echo ""
        echo "Options:"
        echo "  <test-name>  Approve a specific test"
        echo "  --all        Approve all tests (use with caution!)"
        echo ""
        echo "Examples:"
        echo "  $0 startup_empty"
        echo "  $0 --all"
        echo ""
        echo "When to use:"
        echo "  1. Creating a new visual test (first time)"
        echo "  2. Intentionally changing visual appearance"
        echo ""
        echo "Warning:"
        echo "  Only approve changes that you have reviewed and confirmed"
        echo "  are correct. Golden images are the reference for all future"
        echo "  comparisons."
        exit 1
    fi

    if [[ "$1" == "--all" ]]; then
        approve_all
    else
        approve_screenshot "$1"
    fi

    print_summary
}

main "$@"
