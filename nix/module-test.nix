# Evaluates the Home Manager module against stubs for the option paths it writes to, so the
# wiring is checked without pulling home-manager in as an input. Produces the values it would
# emit; flake.nix turns them into assertions
{
  lib,
  pkgs,
  module,
}:

let
  # home-manager's own lib.hm.dag, reduced to what the module uses. Keeping the real shape
  # ({ after, data }) is what makes the "runs after linkGeneration" assertion mean anything
  hmLib = lib // {
    hm.dag.entryAfter = after: data: { inherit after data; };
  };

  stubs =
    { lib, ... }:
    {
      options = {
        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        home.sessionVariables = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        home.activation = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
        xdg.configHome = lib.mkOption {
          type = lib.types.str;
          default = "$HOME/.config";
        };
      };
    };

  eval =
    user:
    (lib.evalModules {
      modules = [
        stubs
        module
        user
      ];
      specialArgs = {
        inherit pkgs;
        lib = hmLib;
      };
    }).config;

  wiredUp = eval { programs.claude-account.enable = true; };

  tuned = eval {
    programs.claude-account = {
      enable = true;
      claudeDir = "/tmp/entry";
      sharedEntries = [
        "settings.json"
        "skills"
      ];
    };
  };

  bare = eval {
    programs.claude-account = {
      enable = true;
      pinConfigDir = false;
      repairOnActivation = false;
    };
  };

  withOpenCode = eval {
    programs.claude-account = {
      enable = true;
      opencode.enable = true;
    };
  };

  off = eval { programs.claude-account.enable = false; };
in
{
  # Joined rather than indexed, so "installed nothing" fails the assertion instead of
  # blowing up during evaluation with an unhelpful list error
  package = lib.concatMapStringsSep " " toString wiredUp.home.packages;
  sessionVariables = wiredUp.home.sessionVariables;
  activation = wiredUp.home.activation;

  tunedConfigDir = tuned.home.sessionVariables.CLAUDE_CONFIG_DIR or null;
  tunedPackage = toString tuned.programs.claude-account.package;

  bareSessionVariables = bare.home.sessionVariables;
  bareActivation = bare.home.activation;

  offPackages = off.home.packages;
  offActivation = off.home.activation;
  offSessionVariables = off.home.sessionVariables;

  opencodePackages = lib.concatMapStringsSep " " toString withOpenCode.home.packages;
  opencodePackage = toString withOpenCode.programs.claude-account.package;
}
