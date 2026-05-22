{ inputs
, prefix ? inputs.self
, systems ? [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ]
, packages ? "packages" # name of dir for the packages
, devShells ? "devShells" # name of dir for the devShells
, hosts ? "hosts" # name of dir for the host configs
, iso ? "${hosts}/iso" # name of dir for the ISO configs
, templates ? "templates" # name of dir for the flake templates
, home ? true
, imports ? [ ]
, ...
}:
let
  flake-parts =
    inputs.flake-parts
      or (throw ''nix-wire uses flake-parts but it is not available in the inputs'');
  lib = inputs.nixpkgs.lib;
  utils = import ./utils.nix
    {
      inherit inputs lib;
    };
in
flake-parts.lib.mkFlake
{
  inherit inputs;
}
{
  inherit systems imports;

  flake = {
    darwinConfigurations = utils.mkDarwinConfigs {
      inherit home;
      dir = "${prefix}/${hosts}/darwin";
    };

    nixosConfigurations = utils.mkNixosConfigs {
      inherit home;
      dir = "${prefix}/${hosts}/nixos";
    };

    isoConfigurations = utils.mkIsoConfigs {
      inherit home;
      dir = "${prefix}/${iso}";
    };

    darwinModules = utils.wireModules {
      dir = "${prefix}/modules/darwin";
    };

    nixosModules = utils.wireModules {
      dir = "${prefix}/modules/nixos";
    };

    homeModules = utils.wireModules {
      dir = "${prefix}/modules/home";
    };

    flakeModules = utils.wireModules {
      dir = "${prefix}/modules/flake";
    };

    overlays = utils.wireOverlays {
      dir = "${prefix}/overlays";
    };

    templates = utils.wireTemplates {
      dir = "${prefix}/${templates}";
    };
  };
  perSystem = { pkgs, system, ... }: {
    # TODO: If community says then expose every package as a overlay
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = lib.attrValues inputs.self.overlays;
    };
    packages = utils.wirePackages {
      inherit pkgs;
      dir = "${prefix}/${packages}";
    };
    devShells = utils.wirePackages {
      inherit pkgs;
      dir = "${prefix}/${devShells}";
    };
    legacyPackages.homeConfigurations = utils.mkHomeConfigs {
      inherit pkgs;
      dir = "${prefix}/${hosts}/home";
    };
  };
}
