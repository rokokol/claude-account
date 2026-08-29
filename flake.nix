{
  description = "Manage Claude Code accounts that share one memory and one set of skills";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Each piece isolated, so a README edit doesn't rebuild anything
      switcher = builtins.path {
        name = "claude-account.sh";
        path = ./claude-account.sh;
      };
      testsDir = builtins.path {
        name = "claude-account-tests";
        path = ./tests;
      };
      completionsDir = builtins.path {
        name = "claude-account-completions";
        path = ./completions;
      };
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = claude-account;
        claude-account = pkgs.callPackage ./nix/package.nix { };
      });

      # homeModules is the name the flake schema knows; homeManagerModules is what most
      # consumers still write, so both point at the same module
      homeModules.default = import ./nix/module.nix { inherit self; };
      homeManagerModules.default = self.homeModules.default;

      # For a consumer who reaches for pkgs rather than this flake's packages directly
      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system}) claude-account;
      };

      checks = forAllSystems (
        pkgs:
        let
          claude-account = self.packages.${pkgs.stdenv.hostPlatform.system}.claude-account;
        in
        {
          # The behaviour suite: a scratch HOME in, a filesystem layout out
          tests =
            pkgs.runCommand "tests"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  gnugrep
                  gnused
                  jq
                  procps
                ];
              }
              ''
                export HOME=$PWD
                mkdir -p repo
                cp ${switcher} repo/claude-account.sh
                cp -r ${testsDir} repo/tests
                cp -r ${completionsDir} repo/completions
                chmod -R +w repo
                patchShebangs repo
                bash repo/tests/run.sh
                touch $out
              '';

          # The wrapper is the whole difference between the repo and the package: it is what
          # makes jq and pgrep reachable from a session that has neither
          package-smoke =
            pkgs.runCommand "package-smoke"
              {
                nativeBuildInputs = [
                  claude-account
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
              }
              ''
                # A deliberately bare PATH: gnugrep is the check's own tool, and everything
                # else the script needs has to come from the wrapper or not at all
                export HOME=$PWD/home PATH=${
                  lib.makeBinPath [
                    claude-account
                    pkgs.coreutils
                    pkgs.gnugrep
                  ]
                }
                mkdir -p "$HOME"
                export XDG_DATA_HOME=$HOME/.local/share

                claude-account add work >/dev/null
                claude-account use work >/dev/null
                test "$(claude-account current)" = work
                test -L "$HOME/.claude"
                # An email is read with jq, which only the wrapper can reach from here
                printf '{"oauthAccount":{"emailAddress":"me@example.com"}}\n' \
                  >"$(claude-account path)/.claude.json"
                claude-account list | grep -F 'me@example.com' >/dev/null
                claude-account --help | grep -F CLAUDE_ACCOUNT_SHARED_DIR >/dev/null
                touch $out
              '';

          # Every setting the module exposes has to reach the script, or it is decoration
          package-settings =
            let
              tuned = claude-account.override {
                sharedEntries = [
                  "settings.json"
                  "skills"
                ];
              };
            in
            pkgs.runCommand "package-settings"
              {
                nativeBuildInputs = [
                  tuned
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
              }
              ''
                export HOME=$PWD/home PATH=${
                  lib.makeBinPath [
                    tuned
                    pkgs.coreutils
                    pkgs.gnugrep
                  ]
                }
                mkdir -p "$HOME"
                export XDG_DATA_HOME=$HOME/.local/share

                claude-account add work >/dev/null
                claude-account use work >/dev/null
                dir=$(claude-account path)
                test -L "$dir/skills" || { echo "a listed entry was not shared"; exit 1; }
                if [ -e "$dir/projects" ]; then
                  echo "an entry outside the configured list was shared anyway"
                  exit 1
                fi
                # …and an unset setting leaves the script's own default as the single source of it
                if grep -q CLAUDE_ACCOUNT ${claude-account}/bin/claude-account; then
                  echo "an unset setting still got baked in"
                  exit 1
                fi
                touch $out
              '';

          # Enabling the module has to be enough to get the switcher, the pin and the repair
          module-wiring =
            let
              wiring = import ./nix/module-test.nix {
                inherit lib pkgs;
                module = self.homeManagerModules.default;
              };
            in
            pkgs.runCommand "module-wiring"
              {
                nativeBuildInputs = [ pkgs.jq ];
                dump = builtins.toJSON wiring;
                passAsFile = [ "dump" ];
              }
              ''
                want() { jq -e "$1" "$dumpPath" >/dev/null || { echo "module wiring: $2"; exit 1; }; }

                want '.package | test("claude-account")' "no switcher installed"
                want '.sessionVariables.CLAUDE_CONFIG_DIR == "$HOME/.claude"' "CLAUDE_CONFIG_DIR is not pinned"
                want '.activation.claudeAccountLinks.data | test("bin/claude-account ensure")' "the links are never repaired"

                # …after linkGeneration, not writeBoundary: that is where the previous
                # generation's files are removed, and it would undo the repair
                want '.activation.claudeAccountLinks.after == ["linkGeneration"]' "the repair runs at the wrong point"

                # A moved entry symlink has to move the pin with it, or the two disagree
                want '.tunedConfigDir == "/tmp/entry"' "the pin did not follow claudeDir"
                want '.tunedPackage != .package' "the settings never reached the package"

                # …and every part of it can be turned off
                want '.bareSessionVariables == {}' "the pin survives pinConfigDir = false"
                want '.bareActivation == {}' "the repair survives repairOnActivation = false"
                want '.offPackages == []' "the switcher is installed while disabled"
                want '.offActivation == {}' "the repair survives enable = false"
                want '.offSessionVariables == {}' "the pin survives enable = false"
                want '.opencodePackages | test("opencode")' "OpenCode is not installed when enabled"

                # Sharing rides on share, not on enable: installing nothing still shares, and
                # only the opt-out has to reach the wrapper as a setting of its own
                want '.unsharedPackages | test("opencode") | not' "OpenCode is installed while disabled"
                want '.opencodePackage == .package' "installing OpenCode changed the switcher"
                want '.unsharedPackage != .package' "the OpenCode opt-out never reached the switcher"
                touch $out
              '';

          scripts-lint =
            pkgs.runCommand "scripts-lint"
              {
                nativeBuildInputs = [
                  pkgs.shellcheck
                  pkgs.shfmt
                  pkgs.zsh
                ];
              }
              ''
                files="${switcher} ${testsDir}/run.sh ${testsDir}/stub/pgrep ${completionsDir}/claude-account.bash"
                # shellcheck disable=SC2086
                shellcheck $files
                # shellcheck disable=SC2086
                shfmt -d -i 2 -ci $files
                # zsh is not shellcheck's language; a parse is what can be checked
                zsh -n ${completionsDir}/_claude-account
                touch $out
              '';
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            jq
            shellcheck
            shfmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
