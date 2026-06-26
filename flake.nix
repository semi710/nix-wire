{
  description = "A Nix wiring system to easily manage/wireup Nix configurations (flake-parts)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }: {
    mkFlake = import ./lib;
    lib =
      let
        utils = import ./lib/utils.nix {
          inputs = { inherit self nixpkgs; };
          lib = nixpkgs.lib;
        };
      in
      {
        inherit (utils) autoImport autoImportExcept;
      };
    apps = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ]
      (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          docs = {
            type = "app";
            program = "${pkgs.python3.withPackages (ps: with ps; [ mkdocs mkdocs-material ])}/bin/mkdocs";
          };
        });
  };
}
