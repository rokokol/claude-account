#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

usage() {
  cat <<EOF
install.sh — install claude-account

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)

The script goes to \$PREFIX/share/claude-account, and \$PREFIX/bin gets a symlink to it.
Everything it needs — bash, jq, pgrep, coreutils — comes from your PATH
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?directory required}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
share="$PREFIX/share/claude-account"

install -Dm755 "$here/claude-account.sh" "$share/claude-account.sh"

install -d "$PREFIX/bin"
ln -sfn ../share/claude-account/claude-account.sh "$PREFIX/bin/claude-account"

echo "installed to $share, linked into $PREFIX/bin"
