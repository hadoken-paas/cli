#!/bin/sh
set -e

VERSION="0.7.0"
REPO="hadoken-paas/cli"
BASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}"

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

    install_dir="/usr/local/bin"
    if [ -w "$install_dir" ]; then
        mv "$tmpdir/$binary" "$install_dir/hadoken"
    else
        printf "Installing to %s (requires sudo)...\n" "$install_dir"
        sudo mv "$tmpdir/$binary" "$install_dir/hadoken"
        sudo chmod +x "$install_dir/hadoken"
    fi
    chmod +x "$install_dir/hadoken"

    printf "Installed to %s/hadoken\n" "$install_dir"
    "$install_dir/hadoken" version
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
# linux/arm64 is not available yet.
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

validate_target "$(detect_os)" "$(detect_arch)"
main
