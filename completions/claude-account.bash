# shellcheck shell=bash
# Bash completion for claude-account. No dependency on the bash-completion package —
# everything used here is bash builtin, and nothing newer than the bash 3.2 a stock
# macOS sources it with.
#
# The command list is spelled here by hand and checked against claude-account by
# check-sh.sh -c in scripts-lint: a command added there fails the gate until it lands
# here and in the zsh file too
_claude_account_profiles() {
  # Live names from the tool itself; the active one leads with a star
  claude-account list 2>/dev/null | awk '{ if ($1 == "*") print $2; else print $1 }'
}

_claude_account() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  local cmd=${COMP_WORDS[1]-}
  local word

  COMPREPLY=()

  if ((COMP_CWORD == 1)); then
    while IFS= read -r word; do
      [[ -n "$word" ]] && COMPREPLY+=("$word")
    done < <(compgen -W "list current use add init ensure path opencode help -v --version" -- "$cur")
    return
  fi

  case "$cmd" in
    init)
      if ((COMP_CWORD == 2)); then
        while IFS= read -r word; do
          [[ -n "$word" ]] && COMPREPLY+=("$word")
        done < <(compgen -W "-f --force" -- "$cur")
      fi
      ;;
    use)
      while IFS= read -r word; do
        [[ -n "$word" ]] && COMPREPLY+=("$word")
      done < <(compgen -W "$(_claude_account_profiles)" -- "$cur")
      ;;
    opencode)
      if ((COMP_CWORD == 2)); then
        while IFS= read -r word; do
          [[ -n "$word" ]] && COMPREPLY+=("$word")
        done < <(compgen -W "init status" -- "$cur")
      fi
      ;;
  esac
}

complete -F _claude_account claude-account
