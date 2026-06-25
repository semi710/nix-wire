{
  description = "Development environment for nix-wire!!";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.flake = false;
  };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = inputs.nixpkgs.lib.systems.flakeExposed;
    imports = [
      (inputs.git-hooks + /flake-module.nix)
    ];
    perSystem = { pkgs, config, ... }: {
      devShells.default = pkgs.mkShell {
        name = "nix-wire";
        meta.description = "Dev environment for nix-wire";
        inputsFrom = [ config.pre-commit.devShell ];
        packages = [ pkgs.just ];
        shellHook = ''
          echo 1>&2 "🐼: $(id -un) | 🧬: $(nix eval --raw --impure --expr 'builtins.currentSystem') | 🐧: $(uname -r) "
          echo 1>&2 "Ready to work on nix-wire!"
        '';
      };

      pre-commit.settings = {
        hooks.nixpkgs-fmt.enable = true;
      };
    };
  };
}
