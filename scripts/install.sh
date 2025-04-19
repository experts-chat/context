#!/bin/sh

# context - Installation Script (Minimal & Styled)
#
# Installs the latest version of the 'context' tool.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
GITHUB_USER="experts-chat"
GITHUB_REPO="context" # Public repo hosting releases
BINARY_NAME="context"
REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO" # Keep for error messages

# --- Styling ---
COLOR_GRAY="\033[90m"           # Gray
COLOR_YELLOW="\033[1;33m"       # Bold Yellow
COLOR_RED="\033[1;31m"          # Bold Red
COLOR_PURPLE="\033[1;38;5;175m" # Bold Color 175 (Purple/Pink)
COLOR_RESET="\033[0m"

# --- Helper Functions ---

# Print message with color and reset using echo -e
_print_color() {
    echo -e "${1}${2}${COLOR_RESET}"
}

# Warnings - Use Yellow
warn() { _print_color "$COLOR_YELLOW" "WARN: $1"; }
# Errors - Use Red
error() { _print_color "$COLOR_RED" "ERROR: $1"; }

# Exit script with error message
fail() {
    error "$1"
    exit 1
}

# Check if a command exists quietly
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Determine OS and Architecture (no output unless error)
get_os_arch() {
    OS_KERNEL=$(uname -s)
    OS_ARCH=$(uname -m)
    case "$OS_KERNEL" in
    Linux) TARGET_OS="linux" ;;
    Darwin) TARGET_OS="darwin" ;;
    *) fail "Unsupported OS: $OS_KERNEL (Linux/macOS only)." ;;
    esac
    case "$OS_ARCH" in
    x86_64 | amd64) TARGET_ARCH="amd64" ;;
    arm64 | aarch64) TARGET_ARCH="arm64" ;;
    *) fail "Unsupported Arch: $OS_ARCH (amd64/arm64 only)." ;;
    esac
}

# Determine checksum tool (no output unless error)
get_checksum_tool() {
    if command_exists sha256sum; then
        CHECKSUM_CMD="sha256sum"
    elif command_exists shasum; then
        if echo "test 1" | shasum -a 256 -c -- >/dev/null 2>&1; then
            CHECKSUM_CMD="shasum -a 256"
        else
            fail "Found 'shasum' but it doesn't support SHA-256."
        fi
    else
        fail "Checksum tool ('sha256sum' or 'shasum') not found. Please install."
    fi
}

# Fetch latest release version tag (no output unless error)
get_latest_release_tag() {
    LATEST_RELEASE_URL="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/releases/latest"
    # Use -sS (silent but show errors) for API call
    LATEST_TAG=$(curl -sSL "$LATEST_RELEASE_URL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || fail "Could not fetch latest release info from GitHub API."
    if [ -z "$LATEST_TAG" ]; then
        fail "Could not determine latest release tag. Check $REPO_URL/releases"
    fi
}

# Verify checksum (no output unless error)
verify_checksum() {
    local file_to_check="$1"
    local checksums_file="$2"
    local expected_filename="$3"
    EXPECTED_CHECKSUM=$(grep "$expected_filename" "$checksums_file" | cut -d ' ' -f 1)
    [ -n "$EXPECTED_CHECKSUM" ] || fail "Could not find checksum for '$expected_filename' in $checksums_file"

    if echo "$CHECKSUM_CMD" | grep -q "sha256sum"; then
        ACTUAL_CHECKSUM=$($CHECKSUM_CMD "$file_to_check" | cut -d ' ' -f 1)
    else
        ACTUAL_CHECKSUM=$($CHECKSUM_CMD "$file_to_check" | cut -d ' ' -f 1)
    fi

    if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
        error "Checksum verification failed!"
        error "Expected: $EXPECTED_CHECKSUM"
        error "Got:      $ACTUAL_CHECKSUM"
        fail "Aborting installation due to checksum mismatch."
    fi
}

# Find best installation directory (no output unless error)
find_install_dir() {
    INSTALL_DIR=""
    CANDIDATE_DIRS="/usr/local/bin $HOME/.local/bin $HOME/bin"
    for dir in $CANDIDATE_DIRS; do
        eval expanded_dir="$dir"
        if [ -d "$expanded_dir" ]; then
            if [ -w "$expanded_dir" ]; then
                INSTALL_DIR="$expanded_dir"
                break
            fi
        else
            parent_dir=$(dirname "$expanded_dir")
            if [ -d "$parent_dir" ] && [ -w "$parent_dir" ]; then
                INSTALL_DIR="$expanded_dir"
                break
            fi
        fi
    done
    if [ -z "$INSTALL_DIR" ]; then
        error "Could not find a writable installation location."
        error "Checked: $CANDIDATE_DIRS"
        error "Please ensure one is writable/creatable or create one and add it to PATH."
        fail "Installation aborted."
    fi
}

# --- Main Installation Logic ---
main() {
    # 1. Initial Setup (Quiet)
    get_os_arch
    get_checksum_tool
    get_latest_release_tag

    # 2. Find Install Location (Quiet)
    find_install_dir # Sets INSTALL_DIR or fails

    # 3. Construct URLs and Filenames (Quiet)
    VERSION_NO_V="${LATEST_TAG#v}"
    ARCHIVE_FILENAME="${BINARY_NAME}_${VERSION_NO_V}_${TARGET_OS}_${TARGET_ARCH}.tar.gz"
    CHECKSUMS_FILENAME="checksums.txt"
    DOWNLOAD_BASE_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$LATEST_TAG"
    ARCHIVE_URL="$DOWNLOAD_BASE_URL/$ARCHIVE_FILENAME"
    CHECKSUMS_URL="$DOWNLOAD_BASE_URL/$CHECKSUMS_FILENAME"

    # 4. Create Temp Dir (Quiet)
    TMP_DIR=$(mktemp -d -t ${BINARY_NAME}_install_XXXXXX)
    trap 'rm -rf "$TMP_DIR"' EXIT # Cleanup trap

    # 5. Download Binary (Show custom message, silent curl)
    _print_color "$COLOR_GRAY" "Downloading $BINARY_NAME $LATEST_TAG for ${TARGET_OS}/${TARGET_ARCH}..."
    curl -sSL "$ARCHIVE_URL" -o "$TMP_DIR/$ARCHIVE_FILENAME" || fail "Download failed: $ARCHIVE_URL"

    # 6. Download Checksum (Silent)
    curl -sSL "$CHECKSUMS_URL" -o "$TMP_DIR/$CHECKSUMS_FILENAME" || fail "Checksum download failed: $CHECKSUMS_URL"

    # 7. Verify Checksum (Quiet)
    verify_checksum "$TMP_DIR/$ARCHIVE_FILENAME" "$TMP_DIR/$CHECKSUMS_FILENAME" "$ARCHIVE_FILENAME"

    # 8. Extract (Quiet)
    tar -xzf "$TMP_DIR/$ARCHIVE_FILENAME" -C "$TMP_DIR" "$BINARY_NAME" || fail "Extraction failed."
    EXTRACTED_BINARY="$TMP_DIR/$BINARY_NAME"
    [ -f "$EXTRACTED_BINARY" ] || fail "Binary '$BINARY_NAME' not found after extraction."

    # 9. Prepare Target Directory (Quiet)
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR" || fail "Failed to create installation directory: $INSTALL_DIR"
    fi

    # 10. Install (Quiet)
    INSTALL_PATH="$INSTALL_DIR/$BINARY_NAME"
    mv "$EXTRACTED_BINARY" "$INSTALL_PATH" || fail "Failed to move binary to $INSTALL_PATH."
    chmod +x "$INSTALL_PATH" || warn "Could not set execute permission on $INSTALL_PATH." # Keep this warning

    # 11. Final Success Message (Styled - exactly as requested)
    _print_color "$COLOR_PURPLE" "> Success! ${BINARY_NAME} has been installed successfully to ${INSTALL_PATH}"

    # 12. PATH Check (Show Warning if needed, keep warnings styled)
    case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;; # Already in PATH, do nothing
    *)
        echo                                                                                 # Add newline spacing before warning
        warn "Directory ${COLOR_PURPLE}${INSTALL_DIR}${COLOR_YELLOW} is not in your \$PATH." # Use Purple for path here too
        warn "You may need to add it to your shell profile (e.g., ~/.bashrc, ~/.zshrc):"
        printf "\n    export PATH=\"%s:\$PATH\"\n\n" "$INSTALL_DIR"
        warn "Restart your shell or source your profile file to apply changes."
        ;;
    esac
}

# --- Run ---
main

