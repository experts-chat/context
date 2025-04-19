#!/bin/sh

# context - Installation Script
#
# This script downloads and installs the latest version of the 'context' tool.
# It attempts to install it into $HOME/.local/bin - ensure this directory
# is in your $PATH.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/context/main/scripts/install.sh | sh
# Or:
#   wget -qO- https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/context/main/scripts/install.sh | sh

set -e # Exit immediately if a command exits with a non-zero status.
# set -u # Treat unset variables as an error - uncomment if needed, but can be strict.
set -o pipefail # Causes pipelines to fail on the first command that fails.

# --- Configuration ---
GITHUB_USER="experts-chat"
GITHUB_REPO="context"
INSTALL_DIR_BASE="$HOME/.local"
INSTALL_DIR="$INSTALL_DIR_BASE/bin"
BINARY_NAME="context"
REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO"

# --- Helper Functions ---

# Simple colored output
_print_in_color() {
    printf "%b%s%b\n" "$1" "$2" "\033[0m"
}
info() { _print_in_color "\033[1;34m" "INFO: $1"; }
warn() { _print_in_color "\033[1;33m" "WARN: $1"; }
error() { _print_in_color "\033[1;31m" "ERROR: $1"; }
success() { _print_in_color "\033[1;32m" "SUCCESS: $1"; }

# Exit script with error message
fail() {
    error "$1"
    exit 1
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Determine OS and Architecture
get_os_arch() {
    OS_KERNEL=$(uname -s)
    OS_ARCH=$(uname -m)

    case "$OS_KERNEL" in
    Linux)
        TARGET_OS="linux"
        ;;
    Darwin)
        TARGET_OS="darwin"
        ;;
    *)
        fail "Unsupported operating system: $OS_KERNEL. Only Linux and macOS are supported."
        ;;
    esac

    case "$OS_ARCH" in
    x86_64 | amd64)
        TARGET_ARCH="amd64"
        ;;
    arm64 | aarch64)
        TARGET_ARCH="arm64"
        ;;
    *)
        fail "Unsupported architecture: $OS_ARCH. Only x86_64 (amd64) and arm64 (aarch64) are supported."
        ;;
    esac
}

# Determine which checksum tool is available
get_checksum_tool() {
    if command_exists sha256sum; then
        CHECKSUM_CMD="sha256sum"
    elif command_exists shasum; then
        # Check if shasum supports SHA256 using a POSIX-compliant pipe
        # Old: if shasum -a 256 -c -- <<< "test 1" >/dev/null 2>&1; then
        if echo "test 1" | shasum -a 256 -c -- >/dev/null 2>&1; then # <-- FIXED LINE
            CHECKSUM_CMD="shasum -a 256"
        else
            fail "Found 'shasum' but it doesn't seem to support SHA-256."
        fi
    else
        fail "Could not find 'sha256sum' or 'shasum'. Please install one to verify downloads."
    fi
}

# Fetch latest release version tag from GitHub API
get_latest_release_tag() {
    LATEST_RELEASE_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/releases/latest"
    info "Fetching latest release information from $LATEST_RELEASE_URL..."

    # Use curl to get the JSON response, grep for tag_name, cut the value.
    # This avoids needing jq, but is more fragile if GitHub changes JSON format.
    LATEST_TAG=$(curl -fsSL "$LATEST_RELEASE_URL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_TAG" ]; then
        fail "Could not determine latest release tag. Check $REPO_URL/releases"
    fi
    info "Latest release tag found: $LATEST_TAG"
}

# Verify checksum of downloaded file
verify_checksum() {
    local file_to_check="$1"
    local checksums_file="$2"
    local expected_filename="$3" # Filename inside checksums.txt

    info "Verifying checksum for $expected_filename..."

    # Extract the expected checksum from the checksums file
    EXPECTED_CHECKSUM=$(grep "$expected_filename" "$checksums_file" | cut -d ' ' -f 1)

    if [ -z "$EXPECTED_CHECKSUM" ]; then
        fail "Could not find checksum for '$expected_filename' in $checksums_file"
    fi

    # Calculate the actual checksum
    # Need to handle different output formats of sha256sum vs shasum
    if echo "$CHECKSUM_CMD" | grep -q "sha256sum"; then
        ACTUAL_CHECKSUM=$($CHECKSUM_CMD "$file_to_check" | cut -d ' ' -f 1)
    else # Assuming shasum
        ACTUAL_CHECKSUM=$($CHECKSUM_CMD "$file_to_check" | cut -d ' ' -f 1)
    fi

    if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
        error "Checksum verification failed!"
        error "Expected: $EXPECTED_CHECKSUM"
        error "Got:      $ACTUAL_CHECKSUM"
        fail "Aborting installation due to checksum mismatch."
    fi
    info "Checksum verified successfully."
}

# --- Main Installation Logic ---
main() {
    info "Starting context installation..."

    # Check dependencies
    info "Checking for required tools (curl, tar, $INSTALL_DIR)..."
    command_exists curl || fail "curl is required but not installed."
    command_exists tar || fail "tar is required but not installed."
    get_checksum_tool # Sets CHECKSUM_CMD or fails

    # Determine platform and latest version
    get_os_arch
    get_latest_release_tag

    # Construct filenames and URLs
    VERSION_NO_V="${LATEST_TAG#v}" # <-- Add this line to strip 'v'
    ARCHIVE_FILENAME="${GITHUB_REPO}_${VERSION_NO_V}_${TARGET_OS}_${TARGET_ARCH}.tar.gz"
    CHECKSUMS_FILENAME="checksums.txt"
    DOWNLOAD_BASE_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$LATEST_TAG"
    ARCHIVE_URL="$DOWNLOAD_BASE_URL/$ARCHIVE_FILENAME"
    CHECKSUMS_URL="$DOWNLOAD_BASE_URL/$CHECKSUMS_FILENAME"

    # Create temporary directory and set cleanup trap
    TMP_DIR=$(mktemp -d -t context_install_XXXXXX)
    trap 'rm -rf "$TMP_DIR"' EXIT # Cleanup trap

    # Download archive and checksums
    info "Downloading archive: $ARCHIVE_URL"
    curl --progress-bar -fL "$ARCHIVE_URL" -o "$TMP_DIR/$ARCHIVE_FILENAME" || fail "Failed to download archive."

    info "Downloading checksums: $CHECKSUMS_URL"
    curl --progress-bar -fL "$CHECKSUMS_URL" -o "$TMP_DIR/$CHECKSUMS_FILENAME" || fail "Failed to download checksums."

    # Verify checksum
    verify_checksum "$TMP_DIR/$ARCHIVE_FILENAME" "$TMP_DIR/$CHECKSUMS_FILENAME" "$ARCHIVE_FILENAME"

    # Extract binary
    info "Extracting $BINARY_NAME from archive..."
    tar -xzf "$TMP_DIR/$ARCHIVE_FILENAME" -C "$TMP_DIR" "$BINARY_NAME" || fail "Failed to extract binary from archive."
    EXTRACTED_BINARY="$TMP_DIR/$BINARY_NAME"
    [ -f "$EXTRACTED_BINARY" ] || fail "Binary not found after extraction."

    # Prepare installation directory
    info "Preparing installation directory: $INSTALL_DIR"
    if [ ! -d "$INSTALL_DIR_BASE" ]; then
        info "Creating base directory $INSTALL_DIR_BASE..."
        mkdir -p "$INSTALL_DIR_BASE" || fail "Failed to create base directory $INSTALL_DIR_BASE."
    fi
    if [ ! -d "$INSTALL_DIR" ]; then
        info "Creating installation directory $INSTALL_DIR..."
        mkdir -p "$INSTALL_DIR" || fail "Failed to create installation directory $INSTALL_DIR."
    fi

    # Check if install directory is writable
    if [ ! -w "$INSTALL_DIR" ]; then
        # Try to check if base dir is writable if install dir failed (might be created by root before)
        if [ ! -w "$INSTALL_DIR_BASE" ]; then
            fail "Installation directory $INSTALL_DIR is not writable. You might need to run with sudo (not recommended) or adjust permissions."
        fi
        # If base is writable but INSTALL_DIR is not, maybe it's owned by root?
        # Try removing and recreating if empty? This is getting risky. Let's just fail clearly.
        fail "Installation directory $INSTALL_DIR exists but is not writable by you. Please check permissions."
    fi

    # Install binary
    INSTALL_PATH="$INSTALL_DIR/$BINARY_NAME"
    info "Installing $BINARY_NAME to $INSTALL_PATH..."
    mv "$EXTRACTED_BINARY" "$INSTALL_PATH" || fail "Failed to move binary to $INSTALL_PATH."
    chmod +x "$INSTALL_PATH" || warn "Failed to set execute permission on $INSTALL_PATH." # Warn instead of fail?

    # Final success message
    success "$BINARY_NAME $LATEST_TAG installed successfully to $INSTALL_PATH"

    # Check if install directory is in PATH and warn if not
    case ":$PATH:" in
    *":$INSTALL_DIR:"*)
        info "$INSTALL_DIR is already in your PATH."
        ;;
    *)
        warn "$INSTALL_DIR is not detected in your PATH environment variable."
        warn "You may need to add it by adding the following line to your shell profile (e.g., ~/.bashrc, ~/.zshrc, ~/.profile):"
        printf "\n    export PATH=\"%s:\$PATH\"\n\n" "$INSTALL_DIR"
        warn "Then, restart your shell or run 'source <your_profile_file>'."
        ;;
    esac

    info "Installation complete."
}

# --- Run the main logic ---
main
