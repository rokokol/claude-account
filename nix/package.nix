# The switcher plus the tools it shells out to. claude-code itself is deliberately NOT a
# runtime input: the whole point is that the stock binary needs no wrapper, and pinning a
# copy here would shadow whichever one the user installed
{
  lib,
  stdenvNoCC,
  installShellFiles,
  makeWrapper,
  bash,
  coreutils,
  gnugrep,
  gnused,
  jq,
  procps,
  # Baked into the wrapper rather than exported as session variables, so a change lands on
  # the next rebuild instead of the next login
  claudeDir ? null,
  profilesDir ? null,
  sharedDir ? null,
  sharedEntries ? null,
  # null leaves the script's default in place; "" is its opt-out from sharing that directory
  opencodeConfigDir ? null,
}:

let
  # Isolated, so editing the README doesn't rebuild the package
  versionFile = builtins.path {
    name = "claude-account-VERSION";
    path = ../VERSION;
  };
  script = builtins.path {
    name = "claude-account.sh";
    path = ../claude-account.sh;
  };
  bashCompletion = builtins.path {
    name = "claude-account.bash";
    path = ../completions/claude-account.bash;
  };
  zshCompletion = builtins.path {
    name = "_claude-account";
    path = ../completions/_claude-account;
  };

  # Left out when unset, so the script's own default stays the single source of it
  setDefault = var: value: lib.optionalString (value != null) ''--set-default ${var} "${value}"'';

  runtimeInputs = [
    coreutils
    gnugrep
    gnused
    jq
    procps
  ];
in

stdenvNoCC.mkDerivation {
  pname = "claude-account";
  # VERSION is the one place the number lives; CI holds CHANGELOG.md to it
  version = lib.fileContents ../VERSION;

  dontUnpack = true;
  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    install -Dm755 ${script} $out/bin/claude-account
    patchShebangs $out/bin
    # --version finds this one prefix over from the wrapped script in bin
    install -Dm644 ${versionFile} $out/share/claude-account/VERSION

    installShellCompletion --bash --name claude-account ${bashCompletion}
    installShellCompletion --zsh --name _claude-account ${zshCompletion}

    # --set-default, not --set: an override from the caller's environment still wins
    wrapProgram $out/bin/claude-account \
      --prefix PATH : ${lib.makeBinPath runtimeInputs} \
      ${setDefault "CLAUDE_ACCOUNT_DIR" claudeDir} \
      ${setDefault "CLAUDE_ACCOUNT_PROFILES_DIR" profilesDir} \
      ${setDefault "CLAUDE_ACCOUNT_SHARED_DIR" sharedDir} \
      ${
        setDefault "CLAUDE_ACCOUNT_SHARED" (
          if sharedEntries == null then null else lib.concatStringsSep " " sharedEntries
        )
      } \
      ${setDefault "CLAUDE_ACCOUNT_OPENCODE_CONFIG_DIR" opencodeConfigDir}

    runHook postInstall
  '';

  meta = {
    description = "Manage Claude Code accounts that share one memory and one set of skills";
    homepage = "https://github.com/rokokol/claude-account";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "claude-account";
  };
}
