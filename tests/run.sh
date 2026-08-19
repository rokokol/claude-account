#!/usr/bin/env bash
# Drives claude-account against a scratch HOME and checks what it did to the filesystem.
#
# Every case gets a fresh HOME *and* a fresh XDG_DATA_HOME: setting HOME alone is not enough,
# because a session that exports XDG_DATA_HOME — home-manager does — would send the test at
# the real profiles. The script is also pointed at scratch dirs explicitly, so even a bug in
# how it derives them cannot reach live data

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")
CA="${CLAUDE_ACCOUNT:-$REPO/claude-account.sh}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# tests/stub shadows pgrep, so "is a session open" is something the suite decides rather
# than something it inherits from the machine
export PATH="$HERE/stub:$PATH"

# A stub that is not executable, or one the PATH does not reach first, silently hands the
# suite the real tool — and for pgrep that is the developer's own running claude
for stub in "$HERE"/stub/*; do
  tool=$(basename "$stub")
  if [[ ! -x $stub ]]; then
    printf 'tests/stub/%s is not executable\n' "$tool" >&2
    exit 1
  fi
  if [[ "$(command -v "$tool")" != "$stub" ]]; then
    printf '%s resolves to %s, not to the stub\n' "$tool" "$(command -v "$tool")" >&2
    exit 1
  fi
done

fails=0
case_name=""

fail() {
  printf '  ✗ %s: %s\n' "$case_name" "$1"
  fails=$((fails + 1))
}

ok() {
  printf '  ✓ %s\n' "$case_name"
}

# A scratch world per case. HOME, XDG dirs and the three overrides all point inside it,
# so nothing here can name a path outside $WORK
world() {
  case_name="$1"
  HOME="$WORK/$1"
  rm -rf "$HOME"
  mkdir -p "$HOME/.local/share"
  export HOME
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CONFIG_HOME="$HOME/.config"
  export CLAUDE_ACCOUNT_DIR="$HOME/.claude"
  export CLAUDE_ACCOUNT_PROFILES_DIR="$XDG_DATA_HOME/claude-profiles"
  export CLAUDE_ACCOUNT_SHARED_DIR="$XDG_DATA_HOME/claude-shared"
  unset CLAUDE_ACCOUNT_SHARED CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR CLAUDECODE FAKE_CLAUDE_RUNNING FAKE_OPENCODE_RUNNING
}

ca() { "$CA" "$@"; }

echo "profiles"

world add-creates-shared-links
ca add work >/dev/null
if [[ -L "$CLAUDE_ACCOUNT_PROFILES_DIR/work/settings.json" &&
  -L "$CLAUDE_ACCOUNT_PROFILES_DIR/work/projects" &&
  -f "$CLAUDE_ACCOUNT_SHARED_DIR/settings.json" ]]; then
  ok
else
  fail "a new profile did not get its links into shared"
fi

world shared-settings-is-valid-json
ca add work >/dev/null
if jq -e . "$CLAUDE_ACCOUNT_SHARED_DIR/settings.json" >/dev/null; then
  ok
else
  fail "the seeded settings.json does not parse — Claude Code would refuse to start"
fi

world links-are-relative
ca add work >/dev/null
target=$(readlink "$CLAUDE_ACCOUNT_PROFILES_DIR/work/skills")
if [[ "$target" != /* && -d "$CLAUDE_ACCOUNT_PROFILES_DIR/work/skills" ]]; then
  ok
else
  fail "link target '$target' is absolute — a sync tool would land it dangling elsewhere"
fi

world profile-dir-is-private
ca add work >/dev/null
perms=$(stat -c %a "$CLAUDE_ACCOUNT_PROFILES_DIR/work")
if [[ "$perms" == 700 ]]; then
  ok
else
  fail "profile dir is $perms, and it holds the OAuth token"
fi

world add-refuses-a-duplicate
ca add work >/dev/null
if ca add work >/dev/null 2>&1; then
  fail "adding the same name twice was allowed"
else
  ok
fi

world add-refuses-a-path-in-the-name
if ca add ../escape >/dev/null 2>&1; then
  fail "a name with a path separator was accepted"
else
  ok
fi

echo "switching"

world use-points-the-entry-symlink
ca add work >/dev/null
ca use work >/dev/null
if [[ "$(readlink "$CLAUDE_ACCOUNT_DIR")" == "$CLAUDE_ACCOUNT_PROFILES_DIR/work" ]]; then
  ok
else
  fail "the entry symlink does not point at the profile"
fi

world current-and-path-follow-use
ca add work >/dev/null
ca add play >/dev/null
ca use play >/dev/null
if [[ "$(ca current)" == play && "$(ca path)" == "$CLAUDE_ACCOUNT_PROFILES_DIR/play" ]]; then
  ok
else
  fail "current/path disagree with the entry symlink"
fi

world current-fails-before-any-use
ca add work >/dev/null
if ca current >/dev/null 2>&1; then
  fail "current invented an active profile where none was picked"
else
  ok
fi

world use-refuses-an-unknown-profile
if ca use nope >/dev/null 2>&1; then
  fail "switching to a profile that does not exist was allowed"
else
  ok
fi

world list-marks-the-active-one
ca add work >/dev/null
ca add play >/dev/null
ca use play >/dev/null
printf '{"oauthAccount":{"emailAddress":"me@example.com"}}\n' \
  >"$CLAUDE_ACCOUNT_PROFILES_DIR/play/.claude.json"
out=$(ca list)
if grep -qE '^\* play +me@example\.com$' <<<"$out" &&
  grep -qE '^ +work +not logged in$' <<<"$out"; then
  ok
else
  fail "list did not mark the active profile or read its email"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

echo "ensure"

world ensure-adds-a-new-shared-entry
ca add work >/dev/null
ca use work >/dev/null
# What a release adding a shared entry looks like: it exists in shared, not yet in the profile
mkdir -p "$CLAUDE_ACCOUNT_SHARED_DIR/hooks"
CLAUDE_ACCOUNT_SHARED="settings.json hooks" ca ensure
if [[ -L "$CLAUDE_ACCOUNT_PROFILES_DIR/work/hooks" ]]; then
  ok
else
  fail "ensure did not link the entry that appeared in shared"
fi

world ensure-keeps-a-real-file
ca add work >/dev/null
ca use work >/dev/null
rm "$CLAUDE_ACCOUNT_PROFILES_DIR/work/settings.json"
printf 'mine\n' >"$CLAUDE_ACCOUNT_PROFILES_DIR/work/settings.json"
ca ensure 2>/dev/null
if [[ "$(cat "$CLAUDE_ACCOUNT_PROFILES_DIR/work/settings.json")" == mine ]]; then
  ok
else
  fail "ensure replaced a real file with a symlink and ate its contents"
fi

world ensure-is-quiet-without-a-profile
if ca ensure 2>/dev/null; then
  ok
else
  fail "ensure failed where home-manager activation calls it on a fresh machine"
fi

world ensure-shares-opencode-when-configured
mkdir -p "$XDG_CONFIG_HOME/opencode"
printf '{"plugin":[]}' >"$XDG_CONFIG_HOME/opencode/opencode.json"
CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR="$XDG_CONFIG_HOME/opencode" ca ensure >/dev/null 2>&1
if [[ -L "$XDG_CONFIG_HOME/opencode" &&
  "$(cat "$CLAUDE_ACCOUNT_SHARED_DIR/opencode/opencode.json")" == '{"plugin":[]}' ]]; then
  ok
else
  fail "ensure did not migrate the configured OpenCode directory"
fi

world ensure-shares-default-opencode-config
mkdir -p "$XDG_CONFIG_HOME/opencode"
printf '{"plugin":[]}' >"$XDG_CONFIG_HOME/opencode/opencode.json"
ca ensure >/dev/null 2>&1
if [[ -L "$XDG_CONFIG_HOME/opencode" &&
  "$(cat "$CLAUDE_ACCOUNT_SHARED_DIR/opencode/opencode.json")" == '{"plugin":[]}' ]]; then
  ok
else
  fail "ensure did not migrate the default OpenCode directory"
fi

world ensure-leaves-opencode-alone-when-opted-out
mkdir -p "$XDG_CONFIG_HOME/opencode"
CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR="" ca ensure >/dev/null 2>&1
if [[ ! -L "$XDG_CONFIG_HOME/opencode" && ! -e "$CLAUDE_ACCOUNT_SHARED_DIR/opencode" ]]; then
  ok
else
  fail "ensure migrated the OpenCode directory the empty setting opted out of"
fi

echo "init"

# The shape a pre-profile machine has: a real ~/.claude with a token, shared work and a
# hand-written global memory, plus .claude.json beside it
legacy_world() {
  world "$1"
  mkdir -p "$CLAUDE_ACCOUNT_DIR/projects/a-chat" "$CLAUDE_ACCOUNT_DIR/skills"
  printf 'token\n' >"$CLAUDE_ACCOUNT_DIR/.credentials.json"
  printf 'my rules\n' >"$CLAUDE_ACCOUNT_DIR/CLAUDE.md"
  printf '{"oauthAccount":{"emailAddress":"me@example.com"}}\n' >"$CLAUDE_ACCOUNT_DIR.json"
}

legacy_world init-moves-work-to-shared
ca init laptop >/dev/null
if [[ -d "$CLAUDE_ACCOUNT_SHARED_DIR/projects/a-chat" &&
  -L "$CLAUDE_ACCOUNT_PROFILES_DIR/laptop/projects" &&
  -f "$CLAUDE_ACCOUNT_PROFILES_DIR/laptop/.credentials.json" ]]; then
  ok
else
  fail "the shared work did not move out, or the token did not stay behind"
fi

legacy_world init-keeps-the-account-file-in-the-profile
ca init laptop >/dev/null
if [[ -f "$CLAUDE_ACCOUNT_PROFILES_DIR/laptop/.claude.json" && ! -e "$CLAUDE_ACCOUNT_DIR.json" ]]; then
  ok
else
  fail ".claude.json did not move next to the token it belongs to"
fi

legacy_world init-parks-a-written-global-memory
ca init laptop 2>/dev/null >/dev/null
parked=("$CLAUDE_ACCOUNT_PROFILES_DIR"/laptop/CLAUDE.md.bak-init-*)
if [[ -f "${parked[0]}" && "$(cat "${parked[0]}")" == "my rules" &&
! -s "$CLAUDE_ACCOUNT_SHARED_DIR/CLAUDE.md" ]]; then
  ok
else
  fail "a hand-written CLAUDE.md was auto-promoted to shared instead of being parked"
fi

legacy_world init-leaves-the-entry-symlink-active
ca init laptop >/dev/null
if [[ -L "$CLAUDE_ACCOUNT_DIR" && "$(ca current)" == laptop ]]; then
  ok
else
  fail "the migrated profile was not made active"
fi

legacy_world init-is-idempotent
ca init laptop >/dev/null
if ca init laptop >/dev/null 2>&1 && [[ "$(ca current)" == laptop ]]; then
  ok
else
  fail "a second init did not no-op on an already migrated home"
fi

world init-on-a-clean-home
if ca init laptop >/dev/null 2>&1 && [[ ! -e "$CLAUDE_ACCOUNT_PROFILES_DIR/laptop" ]]; then
  ok
else
  fail "init invented a profile where there was nothing to migrate"
fi

legacy_world init-refuses-from-inside-claude
if CLAUDECODE=1 ca init laptop >/dev/null 2>&1; then
  fail "init moved ~/.claude out from under the session running it"
else
  ok
fi

legacy_world init-refuses-while-a-session-is-open
if FAKE_CLAUDE_RUNNING=1 ca init laptop >/dev/null 2>&1; then
  fail "init moved ~/.claude while a session still had it open"
else
  ok
fi

legacy_world init-force-overrides-a-live-session
if FAKE_CLAUDE_RUNNING=1 ca init --force laptop >/dev/null 2>&1 && [[ "$(ca current)" == laptop ]]; then
  ok
else
  fail "--force did not get past the live-session check"
fi

world use-warns-but-switches-while-a-session-is-open
ca add work >/dev/null
warning=$(FAKE_CLAUDE_RUNNING=1 ca use work 2>&1 >/dev/null)
if [[ "$(ca current)" == work && "$warning" == *running* ]]; then
  ok
else
  fail "switching with a session open should warn and still switch"
fi

echo "opencode"

world opencode-init-moves-config-to-shared
mkdir -p "$XDG_CONFIG_HOME/opencode"
printf '{"plugin":[]}' >"$XDG_CONFIG_HOME/opencode/opencode.json"
ca opencode init >/dev/null
if [[ -L "$XDG_CONFIG_HOME/opencode" &&
  "$(cat "$CLAUDE_ACCOUNT_SHARED_DIR/opencode/opencode.json")" == '{"plugin":[]}' ]]; then
  ok
else
  fail "opencode init did not move config into shared"
fi

world opencode-init-ignores-the-ensure-opt-out
mkdir -p "$XDG_CONFIG_HOME/opencode"
CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR="" ca opencode init >/dev/null
if [[ -L "$XDG_CONFIG_HOME/opencode" ]]; then
  ok
else
  fail "an explicit opencode init obeyed the opt-out meant for ensure"
fi

world opencode-init-is-idempotent
mkdir -p "$XDG_CONFIG_HOME/opencode"
ca opencode init >/dev/null
if ca opencode init >/dev/null && [[ -L "$XDG_CONFIG_HOME/opencode" ]]; then
  ok
else
  fail "a second opencode init did not preserve the shared link"
fi

world opencode-init-refuses-a-conflict
mkdir -p "$XDG_CONFIG_HOME/opencode" "$CLAUDE_ACCOUNT_SHARED_DIR/opencode"
if ca opencode init >/dev/null 2>&1; then
  fail "opencode init overwrote two existing configuration directories"
else
  ok
fi

world opencode-init-refuses-a-live-session
mkdir -p "$XDG_CONFIG_HOME/opencode"
if FAKE_OPENCODE_RUNNING=1 ca opencode init >/dev/null 2>&1 || [[ -L "$XDG_CONFIG_HOME/opencode" ]]; then
  fail "opencode init moved config out from under a live session"
else
  ok
fi

world opencode-status-reports-local-and-shared
local_status=$(ca opencode status)
ca opencode init >/dev/null
shared_status=$(ca opencode status)
if [[ "$local_status" == OpenCode\ config:\ local* && "$shared_status" == OpenCode\ config:\ shared* ]]; then
  ok
else
  fail "opencode status did not distinguish local and shared config"
fi

echo "cli"

world help-lists-the-commands
if ca --help | grep -q 'claude-account use <name>' && ca --help | grep -q 'claude-account opencode init'; then
  ok
else
  fail "--help does not document the commands"
fi

world help-lists-the-environment
if ca --help | grep -q CLAUDE_ACCOUNT_SHARED_DIR; then
  ok
else
  fail "--help does not document the environment"
fi

world unknown-command-fails
if ca frobnicate >/dev/null 2>&1; then
  fail "an unknown command exited 0"
else
  ok
fi

if ((fails)); then
  printf '\n%d failed\n' "$fails"
  exit 1
fi
printf '\nall passed\n'
