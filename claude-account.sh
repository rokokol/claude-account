#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
claude-account.sh — Claude Code profile switcher (one system user, several accounts)

Usage:
  claude-account list          list profiles with email, active one marked with a star
  claude-account current       name of the active profile
  claude-account use <name>    make a profile active
  claude-account add <name>    create a new profile (then /login inside claude)
  claude-account init [-f] [name [email]]
                               migrate an existing ~/.claude into a profile (name
                               defaults to the hostname; email is read from .claude.json).
                               Does nothing if ~/.claude is already the entry symlink. Run
                               from a clean terminal with no claude sessions open;
                               -f/--force skips the running-session check
  claude-account ensure        repair the active profile's symlinks (home-manager calls this)
  claude-account path          path of the active profile
  claude-account opencode init move OpenCode config into the shared directory. Refuses while
                               an opencode session is open — it reads its settings and plugins
                               at startup, so swapping the directory under it loses writes
  claude-account opencode status
                               show whether OpenCode config is shared
  claude-account --help        this help
  claude-account --version     print the version

~/.claude is a symlink to the active profile, so the stock claude binary needs no wrapper and
switching is one ln -sfn. CLAUDE_CONFIG_DIR is pinned to $HOME/.claude by home-manager — the
same constant for every account: the binary looks for .claude.json beside the config dir rather
than inside it and rewrites it with rename(2), which would turn a symlink at that path into a
regular file. Pinning keeps .claude.json inside the profile, where the rename is harmless

A profile isolates only the account: .credentials.json (OAuth token) and .claude.json (it holds
oauthAccount and userID — the token-to-account binding). Everything else is shared and symlinked
from ~/.local/share/claude-shared: settings.json, CLAUDE.md, plugins/, skills/, commands/,
agents/, plus all the shared work — chats and memory (projects/), command history
(history.jsonl), plans (plans/), tasks (tasks/, todos/) and file-edit history (file-history/).
Claude Code writes through symlinks, so /config, /memory and /resume keep working

.claude.json is per-profile on purpose: it holds oauthAccount, which must live next to the
token, otherwise two parallel sessions would clobber each other's identity. Side effect:
user-scope MCP/integrations and folder trust flags from it are not shared — set up shared
MCP via .mcp.json inside the project

Paths resolve lazily, so a switch reaches sessions that are already running: their next token
refresh lands in the newly active profile. use warns about a live claude but switches anyway

Environment:
  CLAUDE_ACCOUNT_DIR           the entry symlink (default: $HOME/.claude)
  CLAUDE_ACCOUNT_PROFILES_DIR  where profiles live (default: $XDG_DATA_HOME/claude-profiles)
  CLAUDE_ACCOUNT_SHARED_DIR    what they share (default: $XDG_DATA_HOME/claude-shared)
  CLAUDE_ACCOUNT_SHARED        space-separated list of shared entries, replacing the default
  CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR
                               OpenCode config directory ensure keeps shared
                               (default: $XDG_CONFIG_HOME/opencode). Set it empty to keep
                               ensure away from that directory for good; opencode init
                               ignores the opt-out, being an explicit request. ensure only
                               adopts a config that already exists on one side or the other,
                               so a host without OpenCode never grows one
EOF
}

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CLAUDE_DIR="${CLAUDE_ACCOUNT_DIR:-$HOME/.claude}" # the entry symlink CLAUDE_CONFIG_DIR points at
SHARED_DIR="${CLAUDE_ACCOUNT_SHARED_DIR:-$DATA_HOME/claude-shared}"
PROFILES_DIR="${CLAUDE_ACCOUNT_PROFILES_DIR:-$DATA_HOME/claude-profiles}"
# ${VAR-default}, not ${VAR:-default}: an empty value stays empty, which is how ensure is
# told to leave the OpenCode config alone. The explicit opencode commands ignore that
OPENCODE_CONFIG_DIR="${CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR-$CONFIG_HOME/opencode}"

# What every profile shares, all of it plain files a sync tool can carry between machines.
# projects/, history.jsonl, plans/, todos/, tasks/, file-history/ are the shared work: one job
# under whichever account is active — chats and memory, command history, plans, tasks and
# file-edit history.
SHARED_ENTRIES=(
  settings.json CLAUDE.md plugins skills commands agents
  projects history.jsonl plans todos tasks file-history
)

# A space-separated CLAUDE_ACCOUNT_SHARED replaces the list to share more, or less
if [[ -n "${CLAUDE_ACCOUNT_SHARED:-}" ]]; then
  read -ra SHARED_ENTRIES <<<"$CLAUDE_ACCOUNT_SHARED"
fi

die() {
  printf 'claude-account: %s\n' "$1" >&2
  exit 1
}

# The profile name goes into a path, so filter it hard
valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

# A claude-code session shows up with comm "claude" or, when nixpkgs-wrapped, ".claude-wrapped"
claude_running() {
  pgrep -x claude >/dev/null 2>&1 || pgrep -x .claude-wrapped >/dev/null 2>&1
}

# The nixpkgs wrapper renames the real binary to .opencode-wrapped, and comm is capped at 15
# characters, so that is where the kernel cuts it. Matching the full name can never succeed —
# procps says so on stderr and returns 1, which the redirect below would swallow
opencode_running() {
  pgrep -x opencode >/dev/null 2>&1 || pgrep -x '\.opencode-wrapp' >/dev/null 2>&1
}

# Every write below swaps the directory OpenCode reads its settings and plugins from, and it
# reads them at startup — a live session would keep serving the old contents and write the
# new ones back over them. claude survives the same trick because its paths resolve lazily
require_opencode_closed() {
  opencode_running && die "opencode is running — close it before changing its config directory"
  return 0
}

# The entry symlink is the state — nothing else to keep in sync with it. Empty means no profile
# is active yet, so don't invent a default: it would name a profile that need not exist
active_profile() {
  if [[ -L "$CLAUDE_DIR" ]]; then
    basename "$(readlink "$CLAUDE_DIR")"
  fi
}

# A real directory there means the host still has the pre-profile layout
assert_migrated() {
  [[ ! -e "$CLAUDE_DIR" || -L "$CLAUDE_DIR" ]] ||
    die "$CLAUDE_DIR is a real directory — migrate it first: claude-account init"
}

# Which shared entries are files and what an empty one has to contain — everything else in
# SHARED_ENTRIES is a directory. Declared rather than guessed from the name, so adding an
# entry says what it is instead of leaving it to an extension
declare -A SHARED_FILES=(
  # An empty settings.json must still be valid JSON, otherwise Claude Code fails to parse it
  ["settings.json"]='{}'
  ["CLAUDE.md"]=''
  ["history.jsonl"]=''
)

# The shared dir must exist before anything symlinks into it
ensure_shared() {
  local entry

  mkdir -p "$SHARED_DIR"

  for entry in "${SHARED_ENTRIES[@]}"; do
    if [[ -v SHARED_FILES[$entry] ]]; then
      if [[ ! -e "$SHARED_DIR/$entry" ]]; then
        : >"$SHARED_DIR/$entry"
        if [[ -n "${SHARED_FILES[$entry]}" ]]; then
          printf '%s\n' "${SHARED_FILES[$entry]}" >"$SHARED_DIR/$entry"
        fi
      fi
    else
      mkdir -p "$SHARED_DIR/$entry"
    fi
  done
}

# Idempotent: profile dir + symlinks to the shared parts. Overwrites nothing — if a real
# file sits where a symlink should be, it only warns (otherwise one day we'd silently eat
# someone's settings)
ensure_profile() {
  local name="$1"
  local dir="$PROFILES_DIR/$name"
  local entry link target

  ensure_shared
  mkdir -p "$dir"
  chmod 700 "$dir" # holds .credentials.json with OAuth tokens

  for entry in "${SHARED_ENTRIES[@]}"; do
    link="$dir/$entry"

    if [[ ! -e "$SHARED_DIR/$entry" ]]; then
      continue
    fi

    # Relative, so a sync tool carrying the symlink verbatim lands it valid on the other
    # machine — an absolute /home/<someone-else> would dangle there
    target=$(realpath -sm --relative-to="$dir" "$SHARED_DIR/$entry")

    if [[ -L "$link" ]]; then
      # Already our symlink — retarget just in case (broken/moved)
      ln -sfn "$target" "$link"
    elif [[ -e "$link" ]]; then
      printf 'claude-account: %s — regular file, leaving it (expected a symlink to shared)\n' \
        "$link" >&2
    else
      ln -s "$target" "$link"
    fi
  done
}

# A second argument of "adopt" means take over a config that already exists on either side
# but do not conjure one: a host without OpenCode has no business growing a config directory
# for it, and the empty directory would ride the sync to every other host
ensure_opencode_config() {
  local config_dir="$1" mode="${2:-}"
  local shared_config="$SHARED_DIR/opencode"
  local config_parent target actual

  if [[ "$mode" == adopt && ! -e "$config_dir" && ! -L "$config_dir" && ! -e "$shared_config" ]]; then
    return
  fi

  target=$(realpath -m "$shared_config")

  if [[ -L "$config_dir" ]]; then
    actual=$(realpath -m "$config_dir")
    [[ "$actual" == "$target" ]] ||
      die "$config_dir points to $actual, not the shared OpenCode config"
    # Already shared: the activation hook lands here every time, so it must stay a no-op
    # rather than a complaint about whatever session the user has open
    [[ -d "$shared_config" ]] && return
    require_opencode_closed
    mkdir -p "$shared_config"
    return
  fi

  if [[ -e "$config_dir" ]]; then
    [[ -d "$config_dir" ]] || die "$config_dir is not a directory"
    [[ ! -e "$shared_config" ]] ||
      die "$config_dir and $shared_config both exist — merge them by hand"
    require_opencode_closed
    mkdir -p "$SHARED_DIR"
    mv "$config_dir" "$shared_config"
  else
    require_opencode_closed
    mkdir -p "$shared_config"
  fi

  config_parent=$(dirname "$config_dir")
  mkdir -p "$config_parent"
  target=$(realpath -sm --relative-to="$config_parent" "$shared_config")
  ln -s "$target" "$config_dir"
}

profile_email() {
  local cfg="$PROFILES_DIR/$1/.claude.json"

  if [[ -r "$cfg" ]]; then
    jq -r '.oauthAccount.emailAddress // empty' "$cfg" 2>/dev/null || true
  fi
}

cmd_list() {
  local active dir name email mark
  local found=0

  active=$(active_profile)

  for dir in "$PROFILES_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    found=1

    name=$(basename "$dir")
    email=$(profile_email "$name")

    if [[ "$name" == "$active" ]]; then
      mark="*"
    else
      mark=" "
    fi

    printf '%s %-12s %s\n' "$mark" "$name" "${email:-not logged in}"
  done

  ((found)) || die "no profiles, create one: claude-account add <name>"
}

cmd_use() {
  local name="${1:-}"

  [[ -n "$name" ]] || die "give a profile name: claude-account use <name>"
  valid_name "$name" || die "profile name must match [a-zA-Z0-9_-]: $name"
  [[ -d "$PROFILES_DIR/$name" ]] || die "no profile $name, create it: claude-account add $name"
  assert_migrated

  # The swap is followed by live sessions too — their next token refresh writes into the new profile
  if claude_running; then
    printf 'claude-account: claude is running — open sessions follow the switch, close them first\n' >&2
  fi

  ensure_profile "$name"
  ln -sfn "$PROFILES_DIR/$name" "$CLAUDE_DIR"
  printf 'active profile: %s\n' "$name"
}

cmd_add() {
  local name="${1:-}"

  [[ -n "$name" ]] || die "give a profile name: claude-account add <name>"
  valid_name "$name" || die "profile name must match [a-zA-Z0-9_-]: $name"
  [[ ! -d "$PROFILES_DIR/$name" ]] || die "profile $name already exists"

  ensure_profile "$name"
  printf 'profile %s created: %s\n' "$name" "$PROFILES_DIR/$name"
  printf 'next: claude-account use %s, then claude → /login\n' "$name"
}

# home-manager activation calls this: repairs the profile symlinks after a rebuild adds a new
# shared entry. Deliberately never creates the entry symlink — picking a profile is use's job,
# and guessing one here would hide the profiles a half-migrated host already has
cmd_ensure() {
  local name

  if [[ -L "$CLAUDE_DIR" ]]; then
    name=$(active_profile)
    valid_name "$name" || die "broken profile name behind $CLAUDE_DIR: $name"
    ensure_profile "$name"
  else
    if [[ -e "$CLAUDE_DIR" ]]; then
      printf 'claude-account: %s is a real directory — migrate it: claude-account init\n' \
        "$CLAUDE_DIR" >&2
    else
      printf 'claude-account: no active profile yet — pick one: claude-account use <name>\n' >&2
    fi

  fi

  # Empty means opted out of sharing the OpenCode config; see the assignment above
  if [[ -n "$OPENCODE_CONFIG_DIR" ]]; then
    ensure_opencode_config "$OPENCODE_CONFIG_DIR" adopt
  fi
}

cmd_opencode_init() {
  ensure_opencode_config "${OPENCODE_CONFIG_DIR:-$CONFIG_HOME/opencode}"
  printf 'OpenCode config is shared at %s/opencode\n' "$SHARED_DIR"
}

cmd_opencode_status() {
  local config_dir="${OPENCODE_CONFIG_DIR:-$CONFIG_HOME/opencode}"
  local shared_config="$SHARED_DIR/opencode"

  if [[ -L "$config_dir" ]] && [[ "$(realpath -m "$config_dir")" == "$(realpath -m "$shared_config")" ]]; then
    printf 'OpenCode config: shared (%s)\n' "$shared_config"
  else
    printf 'OpenCode config: local (%s)\n' "$config_dir"
  fi
}

cmd_opencode() {
  case "${1:-}" in
    init)
      shift
      cmd_opencode_init "$@"
      ;;
    status)
      shift
      cmd_opencode_status "$@"
      ;;
    *)
      die "usage: claude-account opencode init|status"
      ;;
  esac
}

cmd_current() {
  local name
  name=$(active_profile)

  [[ -n "$name" ]] || die "no active profile, pick one: claude-account use <name>"
  printf '%s\n' "$name"
}

cmd_path() {
  local name
  name=$(active_profile)

  [[ -n "$name" ]] || die "no active profile, pick one: claude-account use <name>"
  printf '%s\n' "$PROFILES_DIR/$name"
}

# Leftover old-location paths in migrated shared files: plugins and statusline remember
# absolute paths from the previous layout
fix_legacy_paths() {
  local name="$1"
  local old="$CLAUDE_DIR"
  local f

  for f in "$SHARED_DIR/plugins/installed_plugins.json" \
    "$SHARED_DIR/plugins/known_marketplaces.json"; do
    if [[ -f "$f" ]]; then
      sed -i "s#$old/plugins#$SHARED_DIR/plugins#g" "$f"
    fi
  done

  # Statusline lives in claude-shared now — if settings remembers the old path, retarget it
  local st="$SHARED_DIR/settings.json"
  if [[ -f "$st" ]] && grep -q "$old" "$st"; then
    local tmp
    tmp=$(mktemp)
    if jq --arg cmd "$SHARED_DIR/statusline.sh" \
      'if .statusLine.command? then .statusLine.command = $cmd else . end' \
      "$st" >"$tmp"; then
      mv "$tmp" "$st"
    else
      rm -f "$tmp"
    fi
  fi

  # Control check: maybe something still references the old path
  if grep -rl "$old" "$SHARED_DIR" "$PROFILES_DIR/$name" 2>/dev/null | grep -q .; then
    printf 'claude-account: references to %s remain, check by hand:\n' "$old" >&2
    grep -rl "$old" "$SHARED_DIR" "$PROFILES_DIR/$name" 2>/dev/null >&2
  fi
}

# One-time migration of an old ~/.claude into a profile. With no args the profile name is
# the hostname. Email is read from .claude.json (it can't be rewritten — the token is bound
# to its own identity); the email argument is optional and only feeds the confirmation line
cmd_init() {
  local force=0
  if [[ "${1:-}" == "-f" || "${1:-}" == "--force" ]]; then
    force=1
    shift
  fi

  local name="${1:-$(uname -n)}"
  local email_arg="${2:-}"
  local legacy_dir="$CLAUDE_DIR"
  # the binary keeps .claude.json beside the config dir, not inside it
  local legacy_json="$CLAUDE_DIR.json"

  # Already the entry symlink — this host is migrated, nothing to pull in
  if [[ -L "$legacy_dir" ]]; then
    printf 'claude-account: %s already points at a profile (%s) — nothing to migrate\n' \
      "$legacy_dir" "$(active_profile)"
    return 0
  fi

  # The trigger is the ~/.claude directory. No dir — nothing to migrate
  if [[ ! -d "$legacy_dir" ]]; then
    printf 'claude-account: no %s — nothing to migrate\n' "$legacy_dir"
    return 0
  fi

  # Never move ~/.claude out from under a live session — it would break it. CLAUDE_CONFIG_DIR is
  # no signal here, it is pinned for every shell; CLAUDECODE is set only inside claude itself
  [[ -z "${CLAUDECODE:-}" ]] ||
    die "init ran from inside claude — exit and run it from a clean terminal"
  if ((!force)) && claude_running; then
    die "claude is running — close every session and run init from a clean terminal (or init --force if sure)"
  fi

  valid_name "$name" || die "profile name must match [a-zA-Z0-9_-]: $name"
  local dir="$PROFILES_DIR/$name"
  [[ ! -e "$dir" ]] || die "profile $name already exists — pick another name"

  # First move all of ~/.claude into the profile, .claude.json next to it
  mkdir -p "$PROFILES_DIR" "$SHARED_DIR"
  mv "$legacy_dir" "$dir"
  if [[ -e "$legacy_json" ]]; then
    mv "$legacy_json" "$dir/.claude.json"
  fi
  chmod 700 "$dir"
  rm -f "$dir/statusline-command.sh" # moved into claude-shared

  local ts
  ts=$(date +%Y%m%d-%H%M%S)

  # CLAUDE.md special case: global memory is curated by hand, never auto-promoted to shared
  # A non-empty one is parked as .bak in the profile for a manual merge; an empty one is
  # dropped. The shared CLAUDE.md stays the (empty) stub ensure_shared makes
  local claude_md="$dir/CLAUDE.md"
  if [[ -f "$claude_md" && ! -L "$claude_md" ]]; then
    if [[ -s "$claude_md" ]]; then
      mv "$claude_md" "$claude_md.bak-init-$ts"
      printf 'claude-account: global CLAUDE.md parked at %s — merge wanted lines into %s\n' \
        "$claude_md.bak-init-$ts" "$SHARED_DIR/CLAUDE.md" >&2
    else
      rm -f "$claude_md"
    fi
  fi

  # Pull the shared entries out into claude-shared. On a fresh machine it is empty, so
  # everything moves as-is; if something is already there, the profile copy goes to .bak so
  # we don't clobber shared. Order matters: this loop runs before ensure_shared/ensure_profile,
  # otherwise those would create empty stubs and the real data would go to .bak instead
  local entry src
  for entry in "${SHARED_ENTRIES[@]}"; do
    [[ "$entry" == CLAUDE.md ]] && continue # handled above
    src="$dir/$entry"
    [[ -e "$src" && ! -L "$src" ]] || continue
    if [[ ! -e "$SHARED_DIR/$entry" ]]; then
      mv "$src" "$SHARED_DIR/$entry"
    else
      mv "$src" "$src.bak-init-$ts"
    fi
  done

  fix_legacy_paths "$name"

  # Profile symlinks to shared + fill in any missing shared dirs
  ensure_profile "$name"

  # Make it active
  ln -sfn "$dir" "$CLAUDE_DIR"

  local email
  email=$(profile_email "$name")
  printf 'profile %s created from %s (%s), active\n' \
    "$name" "$legacy_dir" "${email:-${email_arg:-not logged in}}"
}

case "${1:-}" in
  list)
    shift
    cmd_list "$@"
    ;;
  current)
    shift
    cmd_current "$@"
    ;;
  use)
    shift
    cmd_use "$@"
    ;;
  add)
    shift
    cmd_add "$@"
    ;;
  init)
    shift
    cmd_init "$@"
    ;;
  ensure)
    shift
    cmd_ensure "$@"
    ;;
  path)
    shift
    cmd_path "$@"
    ;;
  opencode)
    shift
    cmd_opencode "$@"
    ;;
  help | -h | --help | "")
    usage
    ;;
  # VERSION sits beside the script (the repo root in a checkout, share/claude-account
  # once installed) or one prefix over (the Nix package wraps the script into bin while
  # VERSION stays in share)
  -v | --version)
    self_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    for v in "$self_dir/VERSION" "$self_dir/../share/claude-account/VERSION"; do
      if [[ -f "$v" ]]; then
        echo "claude-account $(cat "$v")"
        exit 0
      fi
    done
    echo "claude-account unknown"
    ;;
  *)
    die "unknown command: $1 (see --help)"
    ;;
esac
