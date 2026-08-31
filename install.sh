#!/usr/bin/env bash

set -euo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VERSION=$(cat "$here/VERSION")

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
UNINSTALL=0

usage() {
  cat <<EOF
install.sh — install claude-account $VERSION

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)

  -h, --help        show this help and exit
  -v, --version     print the version and exit
      --prefix DIR  install prefix (default: /usr/local)
      --destdir DIR staging root: files land under DESTDIR/PREFIX
      --uninstall   remove everything a previous install wrote, by its manifest

The script goes to \$PREFIX/share/claude-account, and \$PREFIX/bin gets a symlink to it.
A failed preflight names what is missing and prints your distribution's own install
command; nothing is installed on your behalf. claude itself is deliberately not
checked — this tool manages its profiles whether or not the binary is here yet

Runtime environment (read by the installed tool, not this script):
  CLAUDE_ACCOUNT_DIR, CLAUDE_ACCOUNT_PROFILES_DIR, CLAUDE_ACCOUNT_SHARED_DIR, ...
                    every path knob, documented in claude-account --help
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
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -v | --version)
      echo "claude-account $VERSION"
      exit 0
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

if [[ "$PREFIX" != /* ]]; then
  echo "install.sh: PREFIX must be absolute: $PREFIX" >&2
  exit 1
fi

root="${DESTDIR%/}$PREFIX"
share_runtime="$PREFIX/share/claude-account"
share="${DESTDIR%/}$share_runtime"
manifest="$share/install-manifest"

# --- uninstall -------------------------------------------------------------------------

if ((UNINSTALL)); then
  if [[ ! -f "$manifest" ]]; then
    # Installs made before the manifest existed (claude-account <= 1.2.0): the fixed
    # list those versions wrote. Drop this arm one release later
    rm -f \
      "$root/bin/claude-account" \
      "$root/share/bash-completion/completions/claude-account" \
      "$root/share/zsh/site-functions/_claude-account"
    rm -rf "$share"
    echo "removed claude-account from $root"
    exit 0
  fi
  while IFS= read -r path; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    rm -f "${DESTDIR%/}$path"
  done <"$manifest"
  rm -f "$manifest"
  rmdir "$share" 2>/dev/null || true
  echo "removed claude-account from $root"
  exit 0
fi

# --- preflight: refuse loudly, install nothing ----------------------------------------

missing=()

need() { command -v "$1" >/dev/null 2>&1 || missing+=("$1"); }

need install
need jq
need pgrep

distro_id() {
  sed -n 's/^ID\(_LIKE\)\?=//p' "$OS_RELEASE" 2>/dev/null | tr -d '"' | tr '\n' ' '
}

# Missing commands become the distribution's own package names, printed as runnable
# `  $ command` lines — the distro tests run exactly these, so a typo here is a red run
pkg_for() {
  case "$1" in
    pgrep)
      case " $(distro_id) " in
        *" arch "* | *" fedora "*) echo procps-ng ;;
        *) echo procps ;;
      esac
      ;;
    *) echo "$1" ;;
  esac
}

if ((${#missing[@]})); then
  pkgs=()
  for command in "${missing[@]}"; do
    pkgs+=("$(pkg_for "$command")")
  done
  {
    printf 'install.sh: missing dependencies:\n'
    printf '  - %s\n' "${missing[@]}"
    case " $(distro_id) " in
      *" arch "*)
        printf '\nInstall them on Arch:\n'
        printf '  $ sudo pacman -S --needed %s\n' "${pkgs[*]}"
        ;;
      *" debian "* | *" ubuntu "*)
        printf '\nInstall them on Debian/Ubuntu:\n'
        printf '  $ sudo apt-get update\n'
        printf '  $ sudo apt-get install %s\n' "${pkgs[*]}"
        ;;
      *" fedora "*)
        printf '\nInstall them on Fedora:\n'
        printf '  $ sudo dnf install %s\n' "${pkgs[*]}"
        ;;
      *)
        printf '\nInstall them with your package manager: %s\n' "${pkgs[*]}"
        ;;
    esac
  } >&2
  exit 1
fi

# --- install ---------------------------------------------------------------------------
# Every file lands in the manifest as its final runtime path (no DESTDIR): the manifest
# ships inside a staged tree and stays correct wherever the tree ends up

installed=()
rec() { installed+=("${1#"${DESTDIR%/}"}"); }

install -Dm755 "$here/claude-account.sh" "$share/claude-account.sh"
rec "$share/claude-account.sh"
install -Dm644 "$here/VERSION" "$share/VERSION"
rec "$share/VERSION"

install -d "$root/bin"
ln -sfn ../share/claude-account/claude-account.sh "$root/bin/claude-account"
rec "$PREFIX/bin/claude-account"

install -Dm644 "$here/completions/claude-account.bash" "$root/share/bash-completion/completions/claude-account"
rec "$PREFIX/share/bash-completion/completions/claude-account"
install -Dm644 "$here/completions/_claude-account" "$root/share/zsh/site-functions/_claude-account"
rec "$PREFIX/share/zsh/site-functions/_claude-account"

{
  echo "# claude-account $VERSION install manifest"
  printf '%s\n' "${installed[@]}"
} >"$manifest"

echo "installed claude-account $VERSION to $share, linked into $root/bin"
