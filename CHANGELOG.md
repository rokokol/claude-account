# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [1.3.0] - 2026-08-31

### Added

- a `VERSION` file as the one place the version lives: `nix/package.nix` reads it, `claude-account --version`/`-v` and `./install.sh --version`/`-v` print it, and CI refuses a release whose `CHANGELOG.md` has no heading for it
- `-f` as the short form of `init --force`, in the tool and both its completion files
- `--uninstall` by manifest: the install writes `share/claude-account/install-manifest` naming every file it created, and uninstall consumes it — installs made before the manifest are still removed by a fixed list for one release
- a dependency preflight that installs nothing on its own: `jq` and `pgrep` are named with the distribution's own install command as a runnable `$` line; `claude` itself is deliberately never checked
- tab completion for `install.sh` itself (`source completions/install.sh.bash` or `.zsh`), with a drift check that fails the lint when a flag exists in only one of the three places
- distro tests: `tests/distro.sh` installs for real, as root, in `debian`/`ubuntu`/`archlinux`/`fedora` `:latest` containers by running the preflight's own printed guidance, then drives the suite against the installed copy and uninstalls by the manifest; CI runs them on every push to master and weekly, never on pull requests, with one README badge per distribution

### Changed

- the shell lint's file list lives only in the flake's `scripts-lint` check; the CI shell job builds that check instead of repeating the commands

## [1.2.0] - 2026-08-29

### Added

- bash and zsh completions, installed by the package and by `install.sh`; profile names for `use` complete live through `claude-account list`, and the suite checks the spelled command list against the `--help` text

## [1.1.1] - 2026-08-19

### Added

- an empty `CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR` keeps `ensure` away from the OpenCode config directory. The default stayed unreachable since it moved to `$XDG_CONFIG_HOME/opencode`: `${VAR:-default}` reads an empty value as unset
- `opencode.share` to say the same thing from Home Manager

### Fixed

- the guard against a live OpenCode session never fired for a nixpkgs-wrapped binary: `pgrep -x` was given a 17-character name, and `comm` is 15 wide
- every write to the OpenCode config directory now refuses while a session is open, not just the migration; an activation over an already shared config stays a silent no-op
- `ensure` no longer creates an OpenCode config directory on a host that has no OpenCode, where the empty directory would sync on to every other host. It takes over one that already exists, on either side; `opencode init` still sets one up from nothing

### Changed

- `opencode.enable` now only installs the OpenCode package: sharing its config follows `opencode.share`, which is on by default and independent of where OpenCode comes from

## [1.1.0] - 2026-08-18

### Added

- optional OpenCode integration: Home Manager installs it and shares mutable settings and plugin declarations without moving provider auth or package caches
- `claude-account opencode init|status` for the same safe migration outside Nix

### Changed

- `ensure` shares the default `$XDG_CONFIG_HOME/opencode` directory without requiring an explicit setting
- `install.sh` accepts `DESTDIR` independently of `PREFIX`, so package recipes can stage its canonical layout

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where it was a script and an activation hook in the Home Manager configuration

### Added

- `claude-account use|list|current|add|remove`: as many accounts as you need, sharing everything but the tokens
- the profile layout — `.credentials.json` and `.claude.json` per account, everything else symlinked to one shared directory
- `homeModules.default`, which sets `CLAUDE_CONFIG_DIR` and repairs the symlinks on activation, and `overlays.default`
- checks: the suite against a scratch `HOME` and `XDG_DATA_HOME` with a stubbed `pgrep`, the packaged command, its settings, module wiring
