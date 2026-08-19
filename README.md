<div align="center">

# claude-account

**Manage Claude Code accounts that share one memory and one set of skills** (｡･ω･｡)

![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?style=flat&logo=anthropic&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/claude-account/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/claude-account/actions/workflows/build.yml)

</div>

As many accounts on one user as you need — work, personal, a client's — and switching between them is one command. What you do **not** get is a second copy of everything else: the skills, plugins, commands, agents, settings and, above all, the chats, the memory, the plans and the shell history stay **one set that every account uses**

> [!tip]
> It also allows storing all essential data in a single directory (`claude-shared`) and sharing it via tools like Syncthing

That is the whole design. Logging in as someone else changes who pays for the tokens, not who you are on this machine

```sh
claude-account use work    # and the next `claude` is the work account
```

Came over from my rice, **[rokokol/huix](https://github.com/rokokol/huix)**

## Contents

- [How it switches](#how-it-switches)
- [OpenCode](#opencode)
- [What is per-account by default and what is not](#what-is-per-account-by-default-and-what-is-not)
- [Commands](#commands)
- [Install](#install)
  - [Home Manager](#home-manager)
  - [Why CLAUDE_CONFIG_DIR has to be pinned](#why-claude_config_dir-has-to-be-pinned)
  - [Any other distribution](#any-other-distribution)
- [Tests](#tests)
- [Layout](#layout)
- [License](#license)

## How it switches

`~/.claude` is a **symlink** to the active profile. That is the entire mechanism:

```
~/.claude -> ~/.local/share/claude-profiles/work
~/.local/share/
├── claude-profiles/
│   ├── work/                  .credentials.json, .claude.json, links to shared
│   ├── personal/              .credentials.json, .claude.json, links to shared
│   └── …
└── claude-shared/             settings.json, CLAUDE.md, skills/, plugins/, commands/,
                               agents/, projects/, history.jsonl, plans/, tasks/, …
```

So the **stock `claude` binary needs no wrapper**: it looks in `~/.claude` like always, and switching is one `ln -sfn`. Nothing wraps the launch, nothing rewrites your config, and an upgrade of Claude Code cannot break the switching

Paths resolve lazily, so a switch reaches sessions that are already open — their next token refresh lands in the newly active profile. `use` says so and switches anyway

## OpenCode

OpenCode can use the same writable shared directory for its settings and plugin declarations without coupling provider accounts to Claude profiles. Its default config directory, `$XDG_CONFIG_HOME/opencode` (`$HOME/.config/opencode` when `XDG_CONFIG_HOME` is unset), becomes a relative link to `claude-shared/opencode`; `~/.local/share/opencode/auth.json`, sessions and databases remain local. Plugin package caches stay in `~/.cache/opencode`, so another host installs the shared plugin list into its own cache instead of syncing `node_modules`

`ensure` does it, so under Home Manager it happens on activation whether or not the module installs OpenCode — the package can come from anywhere. Set `opencode.share = false`, or `CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR=""` outside Nix, to leave the directory alone; `claude-account opencode init` sets it up on demand either way

## What is per-account by default and what is not

| stays in the profile | is shared |
| --- | --- |
| `.credentials.json` — the OAuth token | `settings.json`, `CLAUDE.md` |
| `.claude.json` — `oauthAccount`, the token-to-account binding | `skills/`, `plugins/`, `commands/`, `agents/` |
| | `projects/` — chats and memory, `history.jsonl` |
| | `plans/`, `tasks/`, `todos/`, `file-history/` |

Claude Code writes **through** symlinks, so `/config`, `/memory` and `/resume` keep working on shared files without knowing anything about this

`.claude.json` also carries user-scope MCP servers and folder-trust flags, and those come along for the ride: they are per-account here, not shared. Put shared MCP in the project's `.mcp.json` instead

Because `claude-shared` is one directory of plain files, pointing a sync tool at it gives you the same skills, chats and memory on another machine. The links into it are **relative**, so they stay valid there instead of naming someone else's `/home`

## Commands

```sh
claude-account list             # profiles with their email, the active one starred
claude-account use <name>       # make one active
claude-account add <name>       # create one, then `claude` → /login
claude-account current          # name of the active profile
claude-account path             # its directory
claude-account ensure           # relink the active profile (the module calls this)
claude-account init [name]      # pull an existing ~/.claude into a profile
claude-account opencode init    # move OpenCode config into claude-shared
claude-account opencode status  # show whether OpenCode config is shared
```

`init` is the one-time migration: it moves your real `~/.claude` into a profile, lifts the shared parts out into `claude-shared`, and points the symlink at it. It refuses to run from inside a Claude session or while one is open, because moving `~/.claude` out from under a live session breaks it — `--force` if you are sure

A hand-written global `CLAUDE.md` is **never** auto-promoted to shared: it is parked next to the profile as `CLAUDE.md.bak-init-<date>` for you to merge by hand, since that file is curated, not accumulated

## Install

### Home Manager

```nix
{
  inputs.claude-account.url = "github:rokokol/claude-account";

  # in your home configuration
  imports = [ inputs.claude-account.homeManagerModules.default ];

  programs.claude-account.enable = true;
  programs.claude-account.opencode.enable = true;
}
```

That installs the switcher, pins `CLAUDE_CONFIG_DIR`, repairs the active profile's links on every activation and keeps the OpenCode config shared; `opencode.enable` adds the OpenCode package itself. Install Claude Code however you already do — this module deliberately does not, so it never fights your pin

| option | what it does | default |
| --- | --- | --- |
| `sharedEntries` | what every profile shares | the table above |
| `sharedDir` / `profilesDir` | where shared data and profiles live | under `$XDG_DATA_HOME` |
| `claudeDir` | the entry symlink | `$HOME/.claude` |
| `pinConfigDir` | export `CLAUDE_CONFIG_DIR` | `true` |
| `repairOnActivation` | run `ensure` on every activation | `true` |
| `opencode.enable` | install the OpenCode package | `false` |
| `opencode.share` | keep the OpenCode config in `claude-shared` | `true` |
| `opencode.configDir` | mutable OpenCode config directory to share | `$XDG_CONFIG_HOME/opencode` |

### Why `CLAUDE_CONFIG_DIR` has to be pinned

`.claude.json` is the file that says **which account the token belongs to** (`oauthAccount`). Left alone, Claude Code keeps it at `~/.claude.json` — in your home directory, *outside* the config directory. That path is one and the same for every profile, so the account binding would sit where switching cannot reach it: swap the symlink and the token changes while the identity does not

Making `~/.claude.json` a symlink into the profile does not help. The file is rewritten by `rename(2)` onto that path, and `rename` replaces the directory entry — so the symlink turns into a regular file the first time Claude Code saves

Pointing `CLAUDE_CONFIG_DIR` at the entry symlink moves the file **inside** the config directory instead. `~/.claude` is the symlink to the active profile, so `.claude.json` lands in the profile, one per account, and the rename happens there where it costs nothing. That is what `pinConfigDir` does, and it is why turning it off breaks account isolation rather than merely changing a path

`repairOnActivation` is the smaller one: it runs `claude-account ensure` after `linkGeneration` — not after `writeBoundary`, because `linkGeneration` is where Home Manager removes the previous generation's files and would undo the repair

### Any other distribution

```sh
git clone https://github.com/rokokol/claude-account
cd claude-account
sudo ./install.sh          # PREFIX=~/.local ./install.sh for a user install
```

Needs `bash` 4+ (associative arrays), `jq`, `pgrep`, and coreutils. Then export `CLAUDE_CONFIG_DIR="$HOME/.claude"` from your shell profile, for the reason above

Package recipes can stage the same layout without duplicating it: `DESTDIR="$pkgdir" PREFIX=/usr ./install.sh`

Nothing there runs `ensure` for you, so the OpenCode config stays where it is until you say otherwise. To share existing settings and plugins, close OpenCode and run:

```sh
claude-account opencode init
```

It moves `~/.config/opencode` to `~/.local/share/claude-shared/opencode` and leaves a relative symlink. Install OpenCode with your distribution's package manager; the non-Nix installer deliberately does not choose one for you

If you do call `ensure` by hand — after an upgrade adds a shared entry, say — it maintains that link too. Export the opt-out from the same shell profile to keep it away from the directory for good:

```sh
export CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR=""
```

`opencode init` ignores it, being an explicit request rather than a background repair

## Tests

```sh
tests/run.sh              # 36 checks, nothing outside a scratch HOME
```

Every case gets a fresh `HOME` **and** a fresh `XDG_DATA_HOME`, and the three path overrides are pointed inside it too. Setting `HOME` alone is not enough — a session that exports `XDG_DATA_HOME`, as Home Manager does, would send the suite at the real profiles. `pgrep` is stubbed, so "is a session open" is something the suite decides rather than something it inherits from the machine running it

`nix flake check` runs that suite plus the packaged wrapper doing a real switch with a bare `PATH`, every setting reaching the script, and the Home Manager module evaluated against option stubs — including that the repair is scheduled after `linkGeneration` and that everything it adds can be turned back off

## Layout

```
claude-account.sh    the switcher
nix/                 package.nix, module.nix, module-test.nix
tests/               run.sh and the pgrep stub
install.sh           for systems without Nix
```

## License

MIT
