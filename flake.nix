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
  };
}
