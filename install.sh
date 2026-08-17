#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"

usage() {
  cat <<EOF
install.sh — install claude-account

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)

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
    --destdir)
      DESTDIR="${2:?directory required}"
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

if [[ -n "$DESTDIR" && "$PREFIX" != /* ]]; then
  echo "install.sh: PREFIX must be absolute when DESTDIR is set: $PREFIX" >&2
  exit 1
fi

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
root="${DESTDIR%/}$PREFIX"
share="$root/share/claude-account"

install -Dm755 "$here/claude-account.sh" "$share/claude-account.sh"

install -d "$root/bin"
ln -sfn ../share/claude-account/claude-account.sh "$root/bin/claude-account"

echo "installed to $share, linked into $root/bin"
