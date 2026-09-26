# file location: flake.nix (repo root)
#
# Packages this repo's four bin/ executables (+ lib/) as an installable Nix flake,
# alongside the existing Homebrew tap (see README.md Installation) -- one more
# distribution channel for the same source tree, not a replacement for any of them.
#
# Usage:
#   nix run github:vraravam/git-remote-gpg-encrypt -- <address>   # git-remote-gpg-encrypt itself
#   nix profile install github:vraravam/git-remote-gpg-encrypt
#
# From another flake (e.g. a home-manager/nix-darwin config):
#   inputs.git-remote-gpg-encrypt.url = "github:vraravam/git-remote-gpg-encrypt";
#   # then reference inputs.git-remote-gpg-encrypt.packages.${system}.default
#
# Deliberately dependency-light, matching this repo's own conventions (see
# AGENTS.md "Quick Facts"): a single nixpkgs input, no flake-utils or other
# flake-level dependency.

{
  description = "Transparent, passphrase-only, encrypted git backups via a git remote helper";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "git-remote-gpg-encrypt";
            # Keep in sync with CHANGELOG.md's latest version and the homebrew-tap
            # Formula's 'tag:'/'revision:' -- this is the flake's equivalent of that
            # formula's pinned release, bumped the same way on every new release.
            version = "0.2.0";

            # Only bin/ and lib/ are actual runtime artifacts -- restricting the
            # source this way means unrelated changes (a CHANGELOG entry, a spec
            # file, this very flake.nix) don't invalidate the build.
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [ ./bin ./lib ];
            };

            nativeBuildInputs = [ pkgs.makeWrapper ];

            # Nothing to compile -- this is a pure-Ruby-stdlib tool (see Gemfile);
            # installPhase below only copies files and wraps them.
            dontBuild = true;

            # bin/git-remote-gpg-encrypt resolves its library via
            # 'require_relative "../lib/git_remote_gpg_encrypt"', so bin/ and lib/
            # must stay siblings under libexec/ -- mirrors the Homebrew formula's
            # 'libexec.install "bin", "lib"' + bin symlinks approach exactly.
            installPhase = ''
              runHook preInstall

              mkdir -p "$out/libexec/git-remote-gpg-encrypt"
              cp -r bin lib "$out/libexec/git-remote-gpg-encrypt/"

              mkdir -p "$out/bin"
              for prog in git-remote-gpg-encrypt git-gpg-encrypt-setup git-gpg-encrypt-verify git-gpg-encrypt-restore; do
                makeWrapper "$out/libexec/git-remote-gpg-encrypt/bin/$prog" "$out/bin/$prog" \
                  --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.git pkgs.gnupg ]}
              done

              runHook postInstall
            '';

            # Intentionally NOT patching the '#!/usr/bin/env ruby' shebangs (no
            # 'ruby' nativeBuildInput, no patchShebangs call): like the Homebrew
            # formula (see its own comment), this targets whatever system Ruby
            # (>= 2.6) is first on PATH at runtime -- macOS ships one by default --
            # rather than pulling in a nix- or Homebrew-managed Ruby for a tool
            # with zero gem dependencies.

            meta = {
              description = "Transparent, passphrase-only, encrypted git backups via a git remote helper";
              homepage = "https://vraravam.github.io/git-remote-gpg-encrypt/";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.unix;
              mainProgram = "git-remote-gpg-encrypt";
            };
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/git-remote-gpg-encrypt";
        };
      });
    };
}
