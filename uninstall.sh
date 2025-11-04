#!/bin/bash
# Aesop Editor - Uninstallation Script
# Safe, interactive uninstaller with config backup
#
# Usage: ./uninstall.sh

set -euo pipefail

# =============================================================================
# COLOR DEFINITIONS
# =============================================================================

# ANSI color codes for pretty output
COLOR_RESET='\033[0m'
COLOR_BOLD='\033[1m'
COLOR_DIM='\033[2m'

# Standard colors
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'

# Bold colors
COLOR_BOLD_RED='\033[1;31m'
COLOR_BOLD_GREEN='\033[1;32m'
COLOR_BOLD_YELLOW='\033[1;33m'
COLOR_BOLD_CYAN='\033[1;36m'

# =============================================================================
# INSTALLATION PATHS
# =============================================================================

# Installation directory
INSTALL_DIR="$HOME/.local/bin"

# Binary paths
WRAPPER_PATH="$INSTALL_DIR/aesop"
BINARY_PATH="$INSTALL_DIR/aesop-bin"

# Configuration directory
CONFIG_DIR="$HOME/.config/aesop"

# Backup directory
BACKUP_DIR="$HOME/.local/share/aesop-backups"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Print colored header
print_header() {
    echo -e "${COLOR_BOLD_YELLOW}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                  Aesop Editor Uninstaller                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
}

# Print step with icon
print_step() {
    echo -e "${COLOR_BOLD}▶${COLOR_RESET} $1"
}

# Print success message
print_success() {
    echo -e "${COLOR_BOLD_GREEN}✓${COLOR_RESET} $1"
}

# Print info message
print_info() {
    echo -e "${COLOR_CYAN}ℹ${COLOR_RESET} $1"
}

# Print warning message
print_warning() {
    echo -e "${COLOR_BOLD_YELLOW}⚠${COLOR_RESET} $1"
}

# Print error message
print_error() {
    echo -e "${COLOR_BOLD_RED}✗${COLOR_RESET} $1" >&2
}

# Print kept item
print_kept() {
    echo -e "${COLOR_BLUE}→${COLOR_RESET} $1"
}

# =============================================================================
# DETECTION
# =============================================================================

detect_installation() {
    print_step "Detecting aesop installation..."

    local found_components=0

    # Check for wrapper script
    if [[ -f "$WRAPPER_PATH" ]]; then
        print_info "Found wrapper: $WRAPPER_PATH"
        found_components=$((found_components + 1))
    fi

    # Check for binary
    if [[ -f "$BINARY_PATH" ]]; then
        local size
        size=$(du -h "$BINARY_PATH" | cut -f1)
        print_info "Found binary: $BINARY_PATH ($size)"
        found_components=$((found_components + 1))
    fi

    # Check for config directory
    if [[ -d "$CONFIG_DIR" ]]; then
        local file_count
        file_count=$(find "$CONFIG_DIR" -type f 2>/dev/null | wc -l | xargs)
        print_info "Found config directory: $CONFIG_DIR ($file_count file(s))"
        found_components=$((found_components + 1))
    fi

    if [[ $found_components -eq 0 ]]; then
        print_error "Aesop does not appear to be installed"
        print_info "No components found at expected locations"
        exit 1
    fi

    print_success "Found $found_components component(s)"
    echo ""
}

# =============================================================================
# CONFIRMATION
# =============================================================================

confirm_uninstall() {
    print_step "Confirm uninstallation"

    echo -e "${COLOR_BOLD}The following will be removed:${COLOR_RESET}"
    if [[ -f "$WRAPPER_PATH" ]]; then
        echo -e "  ${COLOR_RED}✗${COLOR_RESET} $WRAPPER_PATH"
    fi
    if [[ -f "$BINARY_PATH" ]]; then
        echo -e "  ${COLOR_RED}✗${COLOR_RESET} $BINARY_PATH"
    fi
    echo ""

    echo -e "${COLOR_BOLD}Your configuration will be backed up before any removal.${COLOR_RESET}"
    echo ""

    echo -ne "${COLOR_YELLOW}Proceed with uninstallation? [y/N] ${COLOR_RESET}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_error "Uninstallation cancelled by user"
        exit 0
    fi

    echo ""
}

# =============================================================================
# CONFIG BACKUP
# =============================================================================

backup_config() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        print_info "No config directory to backup"
        echo ""
        return
    fi

    print_step "Backing up configuration..."

    # Create backup directory if needed
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        print_info "Created backup directory: $BACKUP_DIR"
    fi

    # Create timestamped tarball
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/aesop-config-$timestamp.tar.gz"

    if tar -czf "$backup_file" -C "$HOME/.config" "aesop" 2>/dev/null; then
        local size
        size=$(du -h "$backup_file" | cut -f1)
        print_success "Config backed up to $backup_file ($size)"
        BACKUP_CREATED="$backup_file"
    else
        print_warning "Failed to create config backup"
        BACKUP_CREATED=""
    fi

    echo ""
}

# =============================================================================
# REMOVAL
# =============================================================================

remove_binaries() {
    print_step "Removing binaries..."

    local removed_count=0

    # Remove wrapper script
    if [[ -f "$WRAPPER_PATH" ]]; then
        rm -f "$WRAPPER_PATH"
        print_success "Removed wrapper: $WRAPPER_PATH"
        removed_count=$((removed_count + 1))
    fi

    # Remove binary
    if [[ -f "$BINARY_PATH" ]]; then
        rm -f "$BINARY_PATH"
        print_success "Removed binary: $BINARY_PATH"
        removed_count=$((removed_count + 1))
    fi

    if [[ $removed_count -eq 0 ]]; then
        print_info "No binaries to remove"
    fi

    echo ""
}

remove_config_directory() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        print_info "No config directory to remove"
        echo ""
        return
    fi

    print_step "Config directory removal"

    echo -e "${COLOR_BOLD}Your configuration has been backed up.${COLOR_RESET}"
    echo -e "Config directory: ${COLOR_CYAN}$CONFIG_DIR${COLOR_RESET}"
    echo ""

    echo -ne "${COLOR_YELLOW}Remove config directory? [y/N] ${COLOR_RESET}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        print_success "Removed config directory: $CONFIG_DIR"
        CONFIG_REMOVED=1
    else
        print_kept "Kept config directory: $CONFIG_DIR"
        CONFIG_REMOVED=0
    fi

    echo ""
}

remove_backup() {
    if [[ -z "${BACKUP_CREATED:-}" ]]; then
        return
    fi

    print_step "Backup cleanup"

    echo -e "Backup file: ${COLOR_CYAN}$BACKUP_CREATED${COLOR_RESET}"
    echo ""

    echo -ne "${COLOR_YELLOW}Remove backup file? [y/N] ${COLOR_RESET}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -f "$BACKUP_CREATED"
        print_success "Removed backup file"
        BACKUP_REMOVED=1
    else
        print_kept "Kept backup: $BACKUP_CREATED"
        BACKUP_REMOVED=0
    fi

    echo ""
}

# =============================================================================
# VERIFICATION
# =============================================================================

verify_removal() {
    print_step "Verifying removal..."

    local still_exists=0

    # Check if wrapper still exists
    if [[ -f "$WRAPPER_PATH" ]]; then
        print_warning "Wrapper still exists: $WRAPPER_PATH"
        still_exists=1
    else
        print_success "Wrapper removed"
    fi

    # Check if binary still exists
    if [[ -f "$BINARY_PATH" ]]; then
        print_warning "Binary still exists: $BINARY_PATH"
        still_exists=1
    else
        print_success "Binary removed"
    fi

    # Report config status
    if [[ ${CONFIG_REMOVED:-0} -eq 1 ]]; then
        if [[ -d "$CONFIG_DIR" ]]; then
            print_warning "Config directory still exists: $CONFIG_DIR"
            still_exists=1
        else
            print_success "Config directory removed"
        fi
    else
        print_info "Config directory kept: $CONFIG_DIR"
    fi

    if [[ $still_exists -ne 0 ]]; then
        print_warning "Some components could not be removed"
    fi

    echo ""
}

# =============================================================================
# SUMMARY
# =============================================================================

print_summary() {
    echo -e "${COLOR_BOLD_GREEN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           Aesop Editor Uninstalled Successfully!               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"

    echo -e "${COLOR_BOLD}Removed:${COLOR_RESET}"
    echo -e "  ${COLOR_RED}✗${COLOR_RESET} Wrapper:  $WRAPPER_PATH"
    echo -e "  ${COLOR_RED}✗${COLOR_RESET} Binary:   $BINARY_PATH"
    if [[ ${CONFIG_REMOVED:-0} -eq 1 ]]; then
        echo -e "  ${COLOR_RED}✗${COLOR_RESET} Config:   $CONFIG_DIR"
    fi
    if [[ ${BACKUP_REMOVED:-0} -eq 1 ]]; then
        echo -e "  ${COLOR_RED}✗${COLOR_RESET} Backup:   ${BACKUP_CREATED:-}"
    fi
    echo ""

    if [[ ${CONFIG_REMOVED:-0} -eq 0 || ${BACKUP_REMOVED:-0} -eq 0 ]]; then
        echo -e "${COLOR_BOLD}Kept:${COLOR_RESET}"
        if [[ ${CONFIG_REMOVED:-0} -eq 0 && -d "$CONFIG_DIR" ]]; then
            echo -e "  ${COLOR_BLUE}→${COLOR_RESET} Config:   $CONFIG_DIR"
        fi
        if [[ ${BACKUP_REMOVED:-0} -eq 0 && -n "${BACKUP_CREATED:-}" ]]; then
            echo -e "  ${COLOR_BLUE}→${COLOR_RESET} Backup:   ${BACKUP_CREATED:-}"
        fi
        echo ""
    fi

    echo -e "${COLOR_DIM}To reinstall: ./install.sh${COLOR_RESET}"
    echo ""
}

# =============================================================================
# MAIN UNINSTALLATION FLOW
# =============================================================================

main() {
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --help)
                echo "Usage: $0"
                echo ""
                echo "Safely uninstalls aesop editor with config backup."
                echo "Interactive prompts will ask about config and backup removal."
                exit 0
                ;;
            *)
                print_error "Unknown option: $arg"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    done

    # Initialize tracking variables
    BACKUP_CREATED=""
    CONFIG_REMOVED=0
    BACKUP_REMOVED=0

    print_header

    # Run uninstallation steps
    detect_installation
    confirm_uninstall
    backup_config
    remove_binaries
    remove_config_directory
    remove_backup
    verify_removal
    print_summary
}

# Run main function
main "$@"
