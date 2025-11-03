#!/usr/bin/env bash
# Visual Regression Testing - Screenshot Comparison Tool
#
# Compares captured screenshots against golden images to detect visual regressions.
#
# Usage:
#   ./compare.sh <test-name>       # Compare single test
#   ./compare.sh --all             # Compare all tests
#
# Exit codes:
#   0 - All comparisons match
#   1 - Differences found

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SCREENSHOTS_DIR="$PROJECT_ROOT/tests/visual/screenshots"
GOLDEN_DIR="$PROJECT_ROOT/tests/visual/golden"
DIFF_DIR="$PROJECT_ROOT/tests/visual/diffs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_diff() { echo -e "${BLUE}[DIFF]${NC} $*"; }

# Statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
MISSING_GOLDEN=0

# Create diff directory
mkdir -p "$DIFF_DIR"

# Compare single screenshot
compare_screenshot() {
    local test_name="$1"
    local screenshot="$SCREENSHOTS_DIR/${test_name}.txt"
    local golden="$GOLDEN_DIR/${test_name}.txt"
    local diff_file="$DIFF_DIR/${test_name}.diff"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ ! -f "$screenshot" ]]; then
        log_error "Screenshot not found: $screenshot"
        log_error "Run: ./capture.sh $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    if [[ ! -f "$golden" ]]; then
        log_warn "Golden image not found: $golden"
        log_warn "Run: ./approve.sh $test_name (to create golden image)"
        MISSING_GOLDEN=$((MISSING_GOLDEN + 1))
        return 1
    fi

    log_info "Comparing: $test_name"

    # Compare using diff
    if diff -u "$golden" "$screenshot" > "$diff_file" 2>&1; then
        log_info "✓ PASS: $test_name - No visual changes detected"
        rm -f "$diff_file"  # Remove empty diff
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "✗ FAIL: $test_name - Visual changes detected"
        log_diff "Diff saved to: $diff_file"

        # Show summary of changes
        local added=$(grep -c "^+" "$diff_file" || echo "0")
        local removed=$(grep -c "^-" "$diff_file" || echo "0")
        log_diff "  Lines added:   $added"
        log_diff "  Lines removed: $removed"

        # Show first few lines of diff
        log_diff "  Preview (first 20 lines):"
        head -20 "$diff_file" | while IFS= read -r line; do
            if [[ "$line" == +* ]]; then
                echo -e "  ${GREEN}$line${NC}"
            elif [[ "$line" == -* ]]; then
                echo -e "  ${RED}$line${NC}"
            else
                echo "  $line"
            fi
        done

        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Compare all screenshots
compare_all() {
    log_info "Comparing all screenshots against golden images..."

    if [[ ! -d "$SCREENSHOTS_DIR" ]] || [[ -z "$(ls -A "$SCREENSHOTS_DIR" 2>/dev/null)" ]]; then
        log_error "No screenshots found in: $SCREENSHOTS_DIR"
        log_error "Run capture.sh to create screenshots first"
        exit 1
    fi

    for screenshot in "$SCREENSHOTS_DIR"/*.txt; do
        # Skip plain versions
        if [[ "$screenshot" == *"_plain.txt" ]]; then
            continue
        fi

        local basename=$(basename "$screenshot" .txt)
        compare_screenshot "$basename"
    done
}

# Print summary
print_summary() {
    echo ""
    log_info "========================================="
    log_info "Visual Regression Test Summary"
    log_info "========================================="
    log_info "Total tests:      $TOTAL_TESTS"
    log_info "Passed:           ${GREEN}$PASSED_TESTS${NC}"
    log_info "Failed:           ${RED}$FAILED_TESTS${NC}"
    log_info "Missing golden:   ${YELLOW}$MISSING_GOLDEN${NC}"

    if [[ $FAILED_TESTS -eq 0 ]] && [[ $MISSING_GOLDEN -eq 0 ]]; then
        log_info "${GREEN}✓ All visual regression tests passed!${NC}"
        return 0
    else
        if [[ $FAILED_TESTS -gt 0 ]]; then
            log_error "${RED}✗ Visual regressions detected!${NC}"
            log_error "Review diffs in: $DIFF_DIR"
            log_error "If changes are intentional, run: ./approve.sh <test-name>"
        fi
        if [[ $MISSING_GOLDEN -gt 0 ]]; then
            log_warn "${YELLOW}⚠ Missing golden images${NC}"
            log_warn "Run: ./approve.sh <test-name> to create golden images"
        fi
        return 1
    fi
}

# Main
main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <test-name> | --all"
        echo ""
        echo "Compare screenshots against golden images for visual regression testing."
        echo ""
        echo "Options:"
        echo "  <test-name>  Compare a specific test"
        echo "  --all        Compare all tests"
        echo ""
        echo "Examples:"
        echo "  $0 startup_empty"
        echo "  $0 --all"
        exit 1
    fi

    if [[ "$1" == "--all" ]]; then
        compare_all
    else
        compare_screenshot "$1"
    fi

    print_summary
    exit $?
}

main "$@"
