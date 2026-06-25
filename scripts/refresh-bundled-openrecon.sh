#!/usr/bin/env bash
# refresh-bundled-openrecon.sh — MAINTAINER tool. Refresh the xz-compressed
# binaries under bin/ from a slainai/openrecon-rs GitHub Release.
#
# The plugin ships one xz-compressed binary per target under bin/. When a new
# openrecon release is cut, run this to pull each target's archive, verify its
# checksum, and re-compress the binary to bin/openrecon-<target>[.exe].xz.
#
# The Windows target (x86_64-pc-windows-msvc) is built out-of-band by the
# manual workflow in the openrecon-rs repo
# (.github/workflows/windows-build.yml, triggered via gh workflow run). It is
# only present on a release once that workflow has run for the tag; this script
# skips it with a warning if the asset is missing.
#
# Usage:
#   scripts/refresh-bundled-openrecon.sh v0.1.0      # pinned tag (recommended)
#   scripts/refresh-bundled-openrecon.sh             # latest v* release
#
# Requires: gh (authenticated), tar, xz, shasum. Commit the updated bin/*.xz
# afterwards under a feat:/fix: PR so semantic-release cuts a plugin release.

set -euo pipefail

REPO="slainai/openrecon-rs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_DIR="${PLUGIN_ROOT}/bin"

# Unix targets ship a bare `openrecon`; Windows ships `openrecon.exe`.
UNIX_TARGETS=(
  aarch64-apple-darwin
  x86_64-apple-darwin
  aarch64-unknown-linux-musl
  x86_64-unknown-linux-musl
)
WIN_TARGET="x86_64-pc-windows-msvc"

die() { echo "refresh-bundled-openrecon: $*" >&2; exit 1; }

command -v gh   >/dev/null 2>&1 || die "gh CLI is required (https://cli.github.com)"
command -v xz   >/dev/null 2>&1 || die "xz is required (macOS: brew install xz; Debian: apt-get install xz-utils)"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

TAG="${1:-}"
if [ -z "$TAG" ]; then
  TAG=$(gh release list -R "$REPO" --limit 50 --json tagName --jq '[.[].tagName | select(test("^v[0-9]"))][0]')
  [ -n "$TAG" ] || die "no v* release found in $REPO"
fi
echo "refresh-bundled-openrecon: $REPO $TAG → $BIN_DIR"

mkdir -p "$BIN_DIR"

# Unix: download the .tar.gz, verify, extract the bare binary, and re-compress
# it to bin/openrecon-<target>.xz (max compression; xz is standard on mac/linux).
# $1 = target triple
pull_unix() {
  local target="$1"
  local asset="openrecon-${target}.tar.gz"
  local sums="openrecon-${target}.sha256"
  local tmp; tmp=$(mktemp -d -t openrecon-refresh-XXXXXX)

  if ! gh release download "$TAG" -R "$REPO" -p "$asset" -p "$sums" -D "$tmp" --clobber 2>/dev/null; then
    rm -rf "$tmp"; return 1
  fi
  ( cd "$tmp" && shasum -a 256 -c "$sums" ) >/dev/null || { rm -rf "$tmp"; die "checksum failed for $target"; }
  tar -xzf "$tmp/$asset" -C "$tmp"
  xz -9 -T0 -c "$tmp/openrecon" > "$BIN_DIR/openrecon-${target}.xz"
  echo "  ✓ openrecon-${target}.xz"
  rm -rf "$tmp"
}

# Windows: download the release .zip, verify its checksum, and commit it AS-IS.
# zip is native on Windows (no xz dependency at install time), so we ship the
# release artifact unchanged.
pull_windows() {
  local target="$1"
  local asset="openrecon-${target}.zip"
  local sums="openrecon-${target}.sha256"
  local tmp; tmp=$(mktemp -d -t openrecon-refresh-XXXXXX)

  if ! gh release download "$TAG" -R "$REPO" -p "$asset" -p "$sums" -D "$tmp" --clobber 2>/dev/null; then
    rm -rf "$tmp"; return 1
  fi
  ( cd "$tmp" && shasum -a 256 -c "$sums" ) >/dev/null || { rm -rf "$tmp"; die "checksum failed for $target"; }
  cp "$tmp/$asset" "$BIN_DIR/openrecon-${target}.zip"
  echo "  ✓ openrecon-${target}.zip (committed as-is)"
  rm -rf "$tmp"
}

for t in "${UNIX_TARGETS[@]}"; do
  pull_unix "$t" || die "missing release asset for $t"
done

# Windows is optional — only present after the manual windows-build workflow ran.
if pull_windows "$WIN_TARGET"; then
  :
else
  echo "  ⚠ Windows asset (openrecon-${WIN_TARGET}.zip) not on release $TAG — skipped." >&2
  echo "    Build it from openrecon-rs: gh workflow run windows-build.yml -f tag=$TAG" >&2
fi

echo "refresh-bundled-openrecon: done. Review and commit bin/ (unix .xz, windows .zip)."
ls -la "$BIN_DIR"
