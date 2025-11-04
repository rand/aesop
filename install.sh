#!/bin/bash
# Aesop Editor - Installation Script
# Clean, safe, non-destructive installer for aesop text editor
#
# Usage: ./install.sh [--skip-build]
#   --skip-build: Use existing zig-out/bin/aesop instead of building

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

# Installation directory (user's local bin)
INSTALL_DIR="$HOME/.local/bin"

# Binary paths
WRAPPER_PATH="$INSTALL_DIR/aesop"
BINARY_PATH="$INSTALL_DIR/aesop-bin"

# Tree-sitter library directory
TREE_SITTER_LIB_DIR="$HOME/lib"

# Configuration directory
CONFIG_DIR="$HOME/.config/aesop"
CONFIG_FILE="$CONFIG_DIR/config.conf"

# Build output path
BUILD_BINARY="zig-out/bin/aesop"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Print colored header
print_header() {
    echo -e "${COLOR_BOLD_CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                   Aesop Editor Installer                       ║"
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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# PRE-INSTALLATION CHECKS
# =============================================================================

check_prerequisites() {
    print_step "Checking prerequisites..."

    local has_errors=0

    # Check for Zig compiler
    if ! command_exists zig; then
        print_error "Zig compiler not found"
        echo "  Install Zig from: https://ziglang.org/download/"
        has_errors=1
    else
        local zig_version
        zig_version=$(zig version)
        print_success "Zig compiler found: $zig_version"
    fi

    # Check for tree-sitter libraries (if not skipping build)
    if [[ "${SKIP_BUILD:-0}" == "0" ]]; then
        if [[ ! -d "$TREE_SITTER_LIB_DIR" ]]; then
            print_warning "Tree-sitter library directory not found: $TREE_SITTER_LIB_DIR"
            print_info "Syntax highlighting may not work without tree-sitter libraries"
            print_info "Install tree-sitter grammars or build will continue without them"
        else
            # Count .dylib files
            local lib_count
            lib_count=$(find "$TREE_SITTER_LIB_DIR" -name "libtree-sitter-*.dylib" 2>/dev/null | wc -l | xargs)
            if [[ "$lib_count" -gt 0 ]]; then
                print_success "Found $lib_count tree-sitter library(ies) in $TREE_SITTER_LIB_DIR"
            else
                print_warning "No tree-sitter libraries found in $TREE_SITTER_LIB_DIR"
            fi
        fi
    fi

    # Check if aesop is already installed
    if [[ -f "$BINARY_PATH" ]]; then
        print_warning "Aesop is already installed at $BINARY_PATH"

        # Get existing binary info
        if [[ -f "$BINARY_PATH" ]]; then
            local size
            size=$(du -h "$BINARY_PATH" | cut -f1)
            local date
            date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$BINARY_PATH" 2>/dev/null || stat -c "%y" "$BINARY_PATH" 2>/dev/null | cut -d'.' -f1)
            print_info "Existing binary: $size, modified $date"
        fi

        # Ask for confirmation
        echo -ne "${COLOR_YELLOW}Overwrite existing installation? [y/N] ${COLOR_RESET}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled by user"
            exit 1
        fi

        # Backup existing binary
        local backup_path="${BINARY_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$BINARY_PATH" "$backup_path"
        print_success "Backed up existing binary to $backup_path"
    fi

    # Check if build exists (if skipping build)
    if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
        if [[ ! -f "$BUILD_BINARY" ]]; then
            print_error "Build binary not found at $BUILD_BINARY"
            print_info "Run 'zig build' first or remove --skip-build flag"
            has_errors=1
        else
            print_success "Found existing build at $BUILD_BINARY"
        fi
    fi

    if [[ $has_errors -ne 0 ]]; then
        print_error "Prerequisites check failed"
        exit 1
    fi

    echo ""
}

# =============================================================================
# BUILD PHASE
# =============================================================================

build_or_copy_binary() {
    if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
        print_step "Skipping build (using existing binary)..."
        print_info "Using: $BUILD_BINARY"
    else
        print_step "Building aesop..."

        # Clean previous build
        if [[ -d "zig-out" ]]; then
            print_info "Cleaning previous build..."
            rm -rf zig-out zig-cache
        fi

        # Build with tree-sitter library path
        print_info "Running: DYLD_LIBRARY_PATH=~/lib zig build"
        if DYLD_LIBRARY_PATH=~/lib zig build 2>&1 | tee /tmp/aesop_build.log; then
            print_success "Build completed successfully"
        else
            print_error "Build failed"
            echo "See /tmp/aesop_build.log for details"
            exit 1
        fi

        # Verify build output
        if [[ ! -f "$BUILD_BINARY" ]]; then
            print_error "Build binary not found at $BUILD_BINARY"
            exit 1
        fi

        # Show build info
        local size
        size=$(du -h "$BUILD_BINARY" | cut -f1)
        print_success "Binary size: $size"
    fi

    echo ""
}

# =============================================================================
# INSTALLATION PHASE
# =============================================================================

install_wrapper_script() {
    print_step "Installing wrapper script..."

    # Create installation directory if it doesn't exist
    if [[ ! -d "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR"
        print_info "Created directory: $INSTALL_DIR"
    fi

    # Create wrapper script that sets DYLD_LIBRARY_PATH
    cat > "$WRAPPER_PATH" << 'EOF'
#!/bin/bash
# Aesop wrapper script - sets environment for tree-sitter libraries
export DYLD_LIBRARY_PATH="$HOME/lib"
exec "$HOME/.local/bin/aesop-bin" "$@"
EOF

    # Make wrapper executable
    chmod +x "$WRAPPER_PATH"

    print_success "Installed wrapper script to $WRAPPER_PATH"
    echo ""
}

install_binary() {
    print_step "Installing binary..."

    # Copy binary to installation directory
    cp "$BUILD_BINARY" "$BINARY_PATH"

    # Make binary executable (should already be, but ensure it)
    chmod +x "$BINARY_PATH"

    # Show installation info
    local size
    size=$(du -h "$BINARY_PATH" | cut -f1)
    print_success "Installed binary to $BINARY_PATH ($size)"

    echo ""
}

# =============================================================================
# CONFIGURATION SETUP
# =============================================================================

setup_config_directory() {
    print_step "Setting up configuration..."

    # Create config directory if it doesn't exist
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        print_success "Created config directory: $CONFIG_DIR"
    else
        print_info "Config directory already exists: $CONFIG_DIR"
    fi

    # Optionally copy example config
    if [[ ! -f "$CONFIG_FILE" ]]; then
        if [[ -f "examples/config.conf.example" ]]; then
            echo -ne "${COLOR_CYAN}Create default config file? [y/N] ${COLOR_RESET}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                cp "examples/config.conf.example" "$CONFIG_FILE"
                print_success "Copied example config to $CONFIG_FILE"
                print_info "Edit $CONFIG_FILE to customize settings"
            else
                print_info "Skipped config file creation (aesop will use defaults)"
            fi
        else
            print_warning "Example config not found at examples/config.conf.example"
            print_info "Aesop will use default settings"
        fi
    else
        print_info "Config file already exists: $CONFIG_FILE"
        print_info "Keeping your existing configuration"
    fi

    echo ""
}

# =============================================================================
# VERIFICATION
# =============================================================================

verify_installation() {
    print_step "Verifying installation..."

    local has_errors=0

    # Check wrapper script
    if [[ -f "$WRAPPER_PATH" && -x "$WRAPPER_PATH" ]]; then
        print_success "Wrapper script: $WRAPPER_PATH"
    else
        print_error "Wrapper script missing or not executable"
        has_errors=1
    fi

    # Check binary
    if [[ -f "$BINARY_PATH" && -x "$BINARY_PATH" ]]; then
        local size
        size=$(du -h "$BINARY_PATH" | cut -f1)
        print_success "Binary: $BINARY_PATH ($size)"
    else
        print_error "Binary missing or not executable"
        has_errors=1
    fi

    # Check config directory
    if [[ -d "$CONFIG_DIR" ]]; then
        print_success "Config directory: $CONFIG_DIR"
    else
        print_warning "Config directory not created"
    fi

    # Try to run aesop with --version flag (if supported)
    # For now, just check if binary can be executed
    if "$BINARY_PATH" --help >/dev/null 2>&1 || [[ $? -ne 127 ]]; then
        print_success "Binary is executable"
    else
        print_warning "Binary may not execute properly"
    fi

    if [[ $has_errors -ne 0 ]]; then
        print_error "Installation verification failed"
        exit 1
    fi

    echo ""
}

check_path() {
    print_step "Checking PATH configuration..."

    if echo "$PATH" | grep -q "$INSTALL_DIR"; then
        print_success "$INSTALL_DIR is in your PATH"
        print_info "You can run aesop from any directory"
    else
        print_warning "$INSTALL_DIR is not in your PATH"
        print_info "Add the following to your shell configuration:"
        echo ""
        echo -e "${COLOR_DIM}  # For bash: ~/.bashrc or ~/.bash_profile"
        echo -e "  # For zsh:  ~/.zshrc"
        echo -e "  export PATH=\"\$HOME/.local/bin:\$PATH\"${COLOR_RESET}"
        echo ""
        print_info "After adding, run: source ~/.zshrc (or your shell's config file)"
    fi

    echo ""
}

# =============================================================================
# SUCCESS MESSAGE
# =============================================================================

print_success_message() {
    echo -e "${COLOR_BOLD_GREEN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              Aesop Editor Installed Successfully!              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"

    echo -e "${COLOR_BOLD}Installation Summary:${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}•${COLOR_RESET} Wrapper:  $WRAPPER_PATH"
    echo -e "  ${COLOR_GREEN}•${COLOR_RESET} Binary:   $BINARY_PATH"
    echo -e "  ${COLOR_GREEN}•${COLOR_RESET} Config:   $CONFIG_DIR"
    echo ""

    echo -e "${COLOR_BOLD}Next Steps:${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}1.${COLOR_RESET} Ensure $INSTALL_DIR is in your PATH (see above)"
    echo -e "  ${COLOR_CYAN}2.${COLOR_RESET} Run ${COLOR_BOLD}aesop${COLOR_RESET} to start editing"
    echo -e "  ${COLOR_CYAN}3.${COLOR_RESET} Run ${COLOR_BOLD}aesop filename${COLOR_RESET} to edit a file"
    echo -e "  ${COLOR_CYAN}4.${COLOR_RESET} Edit $CONFIG_FILE to customize settings"
    echo ""

    echo -e "${COLOR_DIM}Documentation: README_INSTALLATION.md${COLOR_RESET}"
    echo -e "${COLOR_DIM}Uninstall:     ./uninstall.sh${COLOR_RESET}"
    echo ""
}

# =============================================================================
# MAIN INSTALLATION FLOW
# =============================================================================

main() {
    # Parse arguments
    SKIP_BUILD=0
    for arg in "$@"; do
        case $arg in
            --skip-build)
                SKIP_BUILD=1
                shift
                ;;
            --help)
                echo "Usage: $0 [--skip-build]"
                echo ""
                echo "Options:"
                echo "  --skip-build    Use existing build instead of compiling"
                echo "  --help          Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $arg"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    done

    print_header

    # Run installation steps
    check_prerequisites
    build_or_copy_binary
    install_wrapper_script
    install_binary
    setup_config_directory
    verify_installation
    check_path
    print_success_message
}

# Run main function
main "$@"
