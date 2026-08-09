# The switcher plus the tools it shells out to. claude-code itself is deliberately NOT a
# runtime input: the whole point is that the stock binary needs no wrapper, and pinning a
# copy here would shadow whichever one the user installed
{
  lib,
  stdenvNoCC,
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
}:

let
  # Isolated, so editing the README doesn't rebuild the package
  script = builtins.path {
    name = "claude-account.sh";
    path = ../claude-account.sh;
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
  version = "1.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    install -Dm755 ${script} $out/bin/claude-account
    patchShebangs $out/bin

    # --set-default, not --set: an override from the caller's environment still wins
    wrapProgram $out/bin/claude-account \
      --prefix PATH : ${lib.makeBinPath runtimeInputs} \
      ${setDefault "CLAUDE_ACCOUNT_DIR" claudeDir} \
      ${setDefault "CLAUDE_ACCOUNT_PROFILES_DIR" profilesDir} \
      ${setDefault "CLAUDE_ACCOUNT_SHARED_DIR" sharedDir} \
      ${setDefault "CLAUDE_ACCOUNT_SHARED" (
        if sharedEntries == null then null else lib.concatStringsSep " " sharedEntries
      )}

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
