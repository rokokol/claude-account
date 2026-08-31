# shellcheck shell=bash
# bash completion for claude-account. The command list is spelled here by hand;
# tests/run.sh checks it against the --help text, so a command added there fails the
# suite until it lands here
_claude_account_profiles() {
  # Live names from the tool itself; the active one leads with a star
  claude-account list 2>/dev/null | awk '{ if ($1 == "*") print $2; else print $1 }'
}

_claude_account() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  local cmd=${COMP_WORDS[1]-}

  if ((COMP_CWORD == 1)); then
    mapfile -t COMPREPLY < <(compgen -W "list current use add init ensure path opencode help --version" -- "$cur")
    return
  fi

  case "$cmd" in
    init)
      if ((COMP_CWORD == 2)); then
        mapfile -t COMPREPLY < <(compgen -W "-f --force" -- "$cur")
      fi
      ;;
    use)
      mapfile -t COMPREPLY < <(compgen -W "$(_claude_account_profiles)" -- "$cur")
      ;;
    opencode)
      if ((COMP_CWORD == 2)); then
        mapfile -t COMPREPLY < <(compgen -W "init status" -- "$cur")
      fi
      ;;
  esac
}

complete -F _claude_account claude-account
