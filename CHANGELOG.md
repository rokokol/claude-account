# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [1.1.0] - 2026-08-17

### Added

- optional OpenCode integration: Home Manager installs it and shares mutable settings and plugin declarations without moving provider auth or package caches
- `claude-account opencode init|status` for the same safe migration outside Nix

### Changed

- `ensure` shares the default `$XDG_CONFIG_HOME/opencode` directory without requiring an explicit setting

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where it was a script and an activation hook in the Home Manager configuration

### Added

- `claude-account use|list|current|add|remove`: as many accounts as you need, sharing everything but the tokens
- the profile layout — `.credentials.json` and `.claude.json` per account, everything else symlinked to one shared directory
- `homeModules.default`, which sets `CLAUDE_CONFIG_DIR` and repairs the symlinks on activation, and `overlays.default`
- checks: the suite against a scratch `HOME` and `XDG_DATA_HOME` with a stubbed `pgrep`, the packaged command, its settings, module wiring
