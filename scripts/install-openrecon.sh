#!/usr/bin/env bash
# install-openrecon.sh — install the `openrecon` CLI used for LOCAL config
# authoring, validation, and dry-run execution (the recon-authoring skill).
#
# By default it decompresses the xz-compressed binary bundled in bin/ for the
# current platform (no network, no gh) — this is what makes install work inside
# Claude Code / Cowork sandbox mode. Pass --download to fetch the matching
# release archive from GitHub instead (requires gh).
#
# openrecon is stateless: it needs no login, no host config, and no rc-file
# edits. Authoring is entirely local; live-tenant work goes through the
# Flow Service API MCP server, not this binary.
#
# Usage:
#   scripts/install-openrecon.sh                 # bundled binary (default)
#   scripts/install-openrecon.sh --download      # latest GitHub release via gh
#   scripts/install-openrecon.sh --download v0.1.0   # pinned release via gh
#   OPENRECON_INSTALL_DIR=/usr/local/bin sudo -E scripts/install-openrecon.sh

set -euo pipefail

REPO="slainai/openrecon-rs"
INSTALL_DIR="${OPENRECON_INSTALL_DIR:-$HOME/.local/bin}"

DOWNLOAD=0
TAG=""
for arg in "$@"; do
  case "$arg" in
    --download) DOWNLOAD=1 ;;
    -h|--help)  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "install-openrecon: unknown flag: $arg" >&2; exit 2 ;;
    *)          TAG="$arg" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

die() { echo "install-openrecon: $*" >&2; exit 1; }

# Resolve platform → target triple + binary name.
uname_s=$(uname -s)
uname_m=$(uname -m)
EXE=""
IS_WIN=0
case "$uname_s/$uname_m" in
  Linux/x86_64)            TARGET="x86_64-unknown-linux-musl" ;;
  Linux/aarch64|Linux/arm64) TARGET="aarch64-unknown-linux-musl" ;;
  Darwin/x86_64)           TARGET="x86_64-apple-darwin" ;;
  Darwin/arm64)            TARGET="aarch64-apple-darwin" ;;
  # git-bash / MSYS / Cygwin on Windows report MINGW*/MSYS*/CYGWIN*.
  MINGW*/*|MSYS*/*|CYGWIN*/*) TARGET="x86_64-pc-windows-msvc"; EXE=".exe"; IS_WIN=1 ;;
  *) die "unsupported platform: $uname_s/$uname_m (run with --download, or install the Windows .exe by hand — see README)" ;;
esac

mkdir -p "$INSTALL_DIR"
BIN_OUT="$INSTALL_DIR/openrecon${EXE}"

need_xz() {
  command -v xz >/dev/null 2>&1 && return 0
  command -v unxz >/dev/null 2>&1 && return 0
  die "xz (or unxz) is required to decompress the bundled binary. Install it (macOS: brew install xz; Debian/Ubuntu: apt-get install xz-utils) or re-run with --download."
}

# Extract openrecon[.exe] from a .zip into $1 (dir). Prefer unzip; fall back to
# `tar -xf` (bsdtar/Win10 tar reads zip). Used for the Windows artifact.
unzip_into() {
  local zip="$1" dest="$2"
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$zip" -d "$dest"
  elif tar --version >/dev/null 2>&1; then
    tar -xf "$zip" -C "$dest"
  else
    die "need 'unzip' or a zip-capable 'tar' to extract $zip"
  fi
}

if [ "$DOWNLOAD" = "0" ]; then
  # --- bundled path: from bin/ (no gh, no network) ---------------------------
  # Unix targets ship an .xz of the bare binary; Windows ships the release .zip
  # as-is (zip is native on Windows; xz is not).
  if [ "$IS_WIN" = "1" ]; then
    BUNDLED="${PLUGIN_ROOT}/bin/openrecon-${TARGET}.zip"
    [ -f "$BUNDLED" ] || die "bundled binary not found: $BUNDLED (run with --download to fetch from GitHub)"
    TMP=$(mktemp -d -t openrecon-install-XXXXXX); trap 'rm -rf "$TMP"' EXIT
    echo "install-openrecon: extracting bundled binary → $TARGET"
    unzip_into "$BUNDLED" "$TMP"
    install -m 0755 "$(find "$TMP" -name 'openrecon.exe' | head -1)" "$BIN_OUT"
  else
    BUNDLED="${PLUGIN_ROOT}/bin/openrecon-${TARGET}.xz"
    [ -f "$BUNDLED" ] || die "bundled binary not found: $BUNDLED (run with --download to fetch from GitHub)"
    need_xz
    echo "install-openrecon: decompressing bundled binary → $TARGET"
    xz -dc "$BUNDLED" > "$BIN_OUT"
    chmod 0755 "$BIN_OUT"
  fi
else
  # --- download path: fetch the release archive (requires gh) ----------------
  command -v gh >/dev/null 2>&1 || die "gh CLI is required for --download (https://cli.github.com)"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

  if [ -z "$TAG" ]; then
    TAG=$(gh release list -R "$REPO" --limit 50 --json tagName --jq '[.[].tagName | select(test("^v[0-9]"))][0]')
    [ -n "$TAG" ] || die "no v* release found in $REPO"
  fi

  # Windows releases ship a .zip; unix releases ship a .tar.gz.
  if [ "$IS_WIN" = "1" ]; then ASSET="openrecon-${TARGET}.zip"; else ASSET="openrecon-${TARGET}.tar.gz"; fi
  SUMS="openrecon-${TARGET}.sha256"
  TMP=$(mktemp -d -t openrecon-install-XXXXXX)
  trap 'rm -rf "$TMP"' EXIT

  echo "install-openrecon: $REPO $TAG → $TARGET"
  gh release download "$TAG" -R "$REPO" -p "$ASSET" -p "$SUMS" -D "$TMP" --clobber
  ( cd "$TMP" && shasum -a 256 -c "$SUMS" ) >/dev/null || die "checksum verification failed"
  if [ "$IS_WIN" = "1" ]; then
    unzip_into "$TMP/$ASSET" "$TMP"
  else
    tar -xzf "$TMP/$ASSET" -C "$TMP"
  fi
  install -m 0755 "$TMP/openrecon${EXE}" "$BIN_OUT"
fi

echo "install-openrecon: installed $BIN_OUT"
"$BIN_OUT" --version 2>/dev/null || true
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "install-openrecon: NOTE — $INSTALL_DIR is not on PATH; add it or invoke openrecon by full path" >&2 ;;
esac
