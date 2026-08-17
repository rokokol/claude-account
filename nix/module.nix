# Home Manager module. Enabling it installs the switcher, pins CLAUDE_CONFIG_DIR and repairs
# the active profile's links on every activation — the three things that have to be in the
# config rather than done by hand once
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-account;
  exe = lib.getExe cfg.package;
in
{
  options.programs.claude-account = {
    enable = lib.mkEnableOption "the Claude Code profile switcher";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.claude-account.override {
        inherit (cfg)
          claudeDir
          profilesDir
          sharedDir
          sharedEntries
          ;
        opencodeConfigDir = if cfg.opencode.enable then cfg.opencode.configDir else null;
      };
      defaultText = lib.literalExpression "claude-account carrying the settings below";
      description = "The package to install; it carries its own settings";
    };

    claudeDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${config.home.homeDirectory}/.claude";
      description = ''
        The entry symlink Claude Code reads, `$HOME/.claude` by default. Changing it means
        changing `CLAUDE_CONFIG_DIR` to match — `pinConfigDir` does that for you
      '';
    };

    profilesDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${config.xdg.dataHome}/claude-profiles";
      description = "Where the profiles live. Defaults to `$XDG_DATA_HOME/claude-profiles`";
    };

    sharedDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${config.xdg.dataHome}/claude-shared";
      description = ''
        What the profiles share. Defaults to `$XDG_DATA_HOME/claude-shared`. The links into
        it are relative, so pointing this at a synced directory carries them between machines
      '';
    };

    sharedEntries = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      example = [
        "settings.json"
        "skills"
        "projects"
      ];
      description = ''
        Replaces the list of entries every profile shares. An entry is a directory unless it
        is one of the seeded files (`settings.json`, `CLAUDE.md`, `history.jsonl`). Anything
        not listed stays per-profile — which is the right place for `.credentials.json` and
        `.claude.json`, and they are never shareable
      '';
    };

    opencode = {
      enable = lib.mkEnableOption "sharing mutable OpenCode settings and plugins";

      configDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.xdg.configHome}/opencode";
        description = "The mutable OpenCode configuration directory to share";
      };
    };

    pinConfigDir = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Export `CLAUDE_CONFIG_DIR` pointing at the entry symlink. Its only effect is moving
        `.claude.json` inside the profile: the binary keeps that file *beside* the config dir
        and rewrites it with `rename(2)`, which would turn a symlink at that path into a
        regular file. Pinned, the rename happens inside the profile and is harmless
      '';
    };

    repairOnActivation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `claude-account ensure` on every activation, so a release that adds a shared entry
        gets it linked into the active profile without a manual step. It runs after
        `linkGeneration` rather than `writeBoundary`: that is where Home Manager removes the
        previous generation's files, and it would undo the repair
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { home.packages = [ cfg.package ] ++ lib.optional cfg.opencode.enable pkgs.opencode; }

      (lib.mkIf cfg.pinConfigDir {
        home.sessionVariables.CLAUDE_CONFIG_DIR =
          if cfg.claudeDir != null then cfg.claudeDir else "$HOME/.claude";
      })

      (lib.mkIf cfg.repairOnActivation {
        home.activation.claudeAccountLinks = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          ${exe} ensure || true
        '';
      })
    ]
  );
}
