# CLAUDE.md

## What this repo is

As many Claude Code accounts on one user as you need, sharing everything except the tokens. `~/.claude` is a symlink to the active profile; a profile holds only `.credentials.json` and `.claude.json` and symlinks the rest — skills, plugins, commands, agents, settings, chats, memory, plans, history — back to one shared directory. `claude-account use <name>` moves the symlink; there is no state file

The seam in `rokokol/huix` is `home-manager/programs/cli/claude.nix`: the module plus `pkgs.claude-code`. `CLAUDE_CONFIG_DIR` and the activation hook that repairs the symlinks come from the module

## Build / check

```sh
nix build
nix flake check          # tests, the packaged command, its settings, module wiring, shell lint
./tests/run.sh           # a scratch HOME in, a filesystem layout out
PREFIX=$PWD/out ./install.sh
./tests/distro.sh debian # real root install in docker; also ubuntu, arch, fedora
nix fmt -- --ci
```

## Layout

```
claude-account.sh    the switcher
VERSION              the one place the version lives — package.nix, --version and CI read it
completions/         the tool's completions plus install.sh's own, spelled by hand
nix/                 package.nix, module.nix, module-test.nix
tests/               run.sh, distro.sh, check-completions.sh and the pgrep stub
install.sh           for systems without Nix
```

## Things that will bite

- **a scratch `HOME` is not enough.** Home Manager exports `XDG_DATA_HOME` and friends, so a suite that only redirects `HOME` writes into the live data. The suite isolates both, and stubs `pgrep` — otherwise the developer's own running `claude` decides the test
- **the stub guard is not decoration.** `tests/run.sh` refuses to start unless every file in `tests/stub/` is executable and first on `PATH`; a stub left at mode 644 hands the suite the real tool and the failure shows up somewhere else entirely
- **nothing here is declarative on purpose.** The shared directory is plain writable files, because Home Manager would deploy them as `/nix/store/…` symlinks and Syncthing would carry those to a machine where they resolve to nothing

## CHANGELOG

Every user-visible change adds a bullet under `## [Unreleased]` in `CHANGELOG.md`. A release moves those bullets under a new version heading with the date **and bumps `VERSION` in the same commit** — CI refuses a `VERSION` whose heading is missing — then tags `v<x.y.z>` and cuts a `gh release` whose notes are that section. Dates belong in this file and nowhere else — the no-dates rule holds everywhere but here, because Keep a Changelog asks for them
