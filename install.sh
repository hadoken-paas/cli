#!/bin/sh
set -e

VERSION="0.7.0"
REPO="hadoken-paas/cli"
BASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}"
INSTALL_DIR="${HADOKEN_INSTALL:-$HOME/.hadoken}/bin"

main() {
    os="$(detect_os)"
    arch="$(detect_arch)"
    binary="hadoken-${os}-${arch}"
    url="${BASE_URL}/${binary}"
    checksums_url="${BASE_URL}/checksums.txt"

    printf "Installing hadoken v%s (%s/%s)...\n" "$VERSION" "$os" "$arch"

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    download "$url" "$tmpdir/$binary"
    download "$checksums_url" "$tmpdir/checksums.txt"

    verify_checksum "$tmpdir" "$binary"

    mkdir -p "$INSTALL_DIR"
    mv "$tmpdir/$binary" "$INSTALL_DIR/hadoken"
    chmod +x "$INSTALL_DIR/hadoken"

    printf "Installed to %s/hadoken\n" "$INSTALL_DIR"
    "$INSTALL_DIR/hadoken" version

    setup_path
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux" ;;
        *)
            printf "Error: unsupported OS '%s'. Hadoken supports macOS and Linux.\n" "$(uname -s)" >&2
            exit 1
            ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) echo "arm64" ;;
        x86_64)        echo "amd64" ;;
        *)
            printf "Error: unsupported architecture '%s'. Hadoken supports arm64 and x86_64.\n" "$(uname -m)" >&2
            exit 1
            ;;
    esac
}

# Only darwin/arm64, darwin/amd64, linux/amd64 are built.
validate_target() {
    os="$1"
    arch="$2"
    if [ "$os" = "linux" ] && [ "$arch" = "arm64" ]; then
        printf "Error: linux/arm64 is not supported yet.\n" >&2
        exit 1
    fi
}

download() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 60 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=60 -O "$dest" "$url"
    else
        printf "Error: neither curl nor wget found. Install one and try again.\n" >&2
        exit 1
    fi
}

verify_checksum() {
    dir="$1"
    binary="$2"
    expected="$(grep "$binary" "$dir/checksums.txt" | awk '{print $1}')"
    if [ -z "$expected" ]; then
        printf "Error: no checksum found for %s\n" "$binary" >&2
        exit 1
    fi
    if command -v shasum >/dev/null 2>&1; then
        actual="$(cd "$dir" && shasum -a 256 "$binary" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
        actual="$(cd "$dir" && sha256sum "$binary" | awk '{print $1}')"
    else
        printf "Warning: cannot verify checksum (no shasum or sha256sum). Skipping.\n" >&2
        return
    fi
    if [ "$expected" != "$actual" ]; then
        printf "Error: checksum mismatch for %s\n  expected: %s\n  actual:   %s\n" "$binary" "$expected" "$actual" >&2
        exit 1
    fi
}

setup_path() {
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*) return ;;
    esac

    line="export PATH=\"${INSTALL_DIR}:\$PATH\""

    if is_interactive; then
        printf "\n%s is not in your PATH.\n" "$INSTALL_DIR"
        printf "Add it to your shell profile? (Y/n) "
        read -r answer </dev/tty
        case "$answer" in
            [nN]*) print_manual_path "$line"; return ;;
        esac
        append_to_rc "$line"
    else
        print_manual_path "$line"
    fi
}

is_interactive() {
    [ -t 0 ] || [ -t 1 ]
}

detect_rc_file() {
    shell_name="$(basename "${SHELL:-/bin/sh}")"
    case "$shell_name" in
        zsh)  echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash)
            if [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        fish) echo "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

append_to_rc() {
    line="$1"
    rc="$(detect_rc_file)"
    shell_name="$(basename "${SHELL:-/bin/sh}")"

    if [ "$shell_name" = "fish" ]; then
        line="set -gx PATH \"${INSTALL_DIR}\" \$PATH"
    fi

    if [ -f "$rc" ] && grep -qF "$INSTALL_DIR" "$rc" 2>/dev/null; then
        printf "Already in %s\n" "$rc"
        return
    fi

    printf "\n# hadoken\n%s\n" "$line" >> "$rc"
    printf "Added to %s. Restart your shell or run:\n  %s\n" "$rc" "$line"
}

print_manual_path() {
    line="$1"
    printf "To add it manually, add this to your shell profile:\n  %s\n" "$line"
}

validate_target "$(detect_os)" "$(detect_arch)"
main
