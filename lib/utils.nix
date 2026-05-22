{ inputs, lib ? import <nixpkgs/lib>, ... }:

let
  # Remove the ".nix" suffix from a filename
  stripNix = name: lib.removeSuffix ".nix" name;

  # Check if an entry is a regular .nix file
  isNixFile = name: type:
    type == "regular" && lib.hasSuffix ".nix" name;

  # Check if an entry is a directory containing default.nix
  isDirWithDefault = name: type: dir:
    type == "directory" && builtins.pathExists (dir + "/${name}/default.nix");

  # Check if an entry is a directory containing template.nix
  isDirWithTemplate = name: type: dir:
    type == "directory" && builtins.pathExists (dir + "/${name}/template.nix");

  # Read a directory safely; return empty set if it does not exist
  files = dir:
    if builtins.pathExists dir
    then builtins.readDir dir
    else { };

  commonNix = {
    nixpkgs = {
      config.allowUnfree = lib.mkDefault true;
      overlays = lib.attrValues inputs.self.overlays;
    };
    nix = {
      settings = {
        max-jobs = lib.mkDefault "auto";
        experimental-features = lib.mkDefault "nix-command flakes";
      };
    };
  };

  # Filter out foo.nix if foo/default.nix exists
  filterPreferDir = dir: fs:
    lib.filterAttrs
      (name: type:
        !(lib.hasSuffix ".nix" name
          && fs ? ${lib.removeSuffix ".nix" name}
          && isDirWithDefault (lib.removeSuffix ".nix" name) (fs.${lib.removeSuffix ".nix" name}) dir)
      )
      fs;

  commonSpecialArgs = { inherit inputs; flake = inputs.self; };

  # Extract common home-manager modules for nixos/darwin hosts
  #
  # Parameters:
  #   - type: "nixos" | "darwin"
  #   - dir: host config base directory
  #   - hostname: name of the host
  commonHomeModules = type: dir: hostname:
    let
      hmInput =
        inputs.home-manager
          or (throw "nix-wire uses home-manager but it is not available in inputs");

      hmImport =
        if type == "nixos" then
          hmInput.nixosModules.home-manager
        else
          hmInput.darwinModules.home-manager;
    in
    [
      hmImport
      ({ pkgs, ... }: {
        home-manager.useGlobalPkgs = lib.mkDefault true;
        home-manager.useUserPackages = lib.mkDefault true;
        home-manager.backupFileExtension = lib.mkDefault "";
        home-manager.extraSpecialArgs = commonSpecialArgs;
        home-manager.users = getUsersHome dir hostname;
        home-manager.sharedModules = [
          {
            home.sessionPath = lib.mkIf pkgs.stdenv.isDarwin [
              "/etc/profiles/per-user/$USER/bin" # To access home-manager binaries
              "/nix/var/nix/profiles/system/sw/bin" # To access nix-darwin binaries
              "/usr/local/bin" # Some macOS GUI programs install here
            ];
          }
        ];
      })
    ];

  # Build common modules for nixos/darwin hosts
  #
  # Parameters:
  #   - type: "nixos" | "darwin"
  #   - home: boolean, whether to include home-manager modules
  #   - path: path to the host's config file
  #   - dir: base directory for the host configs
  #   - hostname: name of the host
  commonModules = type: home: path: dir: hostname:
    let
      homeModules =
        if home then
          commonHomeModules type dir hostname
        else
          [ ];
    in
    [
      path
      ({ pkgs, ... }: {
        imports = homeModules;
        users.users = getUsers dir hostname pkgs;
      })
      commonNix
    ];

  # ------------------------------------------------------------------------
  # Generic walker function
  #
  # wireGeneric scans a given directory and collects all `.nix` files and
  # subdirectories containing a `default.nix` file into an attribute set.
  #
  # Precedence rule:
  #   - If both `foo.nix` and `foo/default.nix` exist, `foo/default.nix` is used.
  #   - Otherwise, whichever exists is used.
  #
  # Parameters:
  #   - dir: the directory to scan
  #   - buildFn: a function applied to each file or default.nix directory.
  #              Receives two arguments:
  #                1. path: full path to the file or default.nix
  #                2. name: the entry name (filename without .nix or directory name)
  #
  # Returns:
  #   - An attrset mapping:
  #       { name = buildFn(path, name); … }
  #
  # Example usage:
  #   wireGeneric {
  #     dir = ./packages;
  #     buildFn = path: name: pkgs.callPackage path {};
  #   }
  #
  # This modification allows buildFn to be aware of the specific entry it is
  # processing, e.g., hostnames, usernames, or package names.
  # ------------------------------------------------------------------------
  wireGeneric = { dir, buildFn, isDirAccepted ? isDirWithDefault }:
    let fs = filterPreferDir dir (files dir); in
    lib.foldlAttrs
      (acc: name: type:
        if isDirAccepted name type dir then
          acc // { ${name} = buildFn (dir + "/" + name) name; }
        else if isNixFile name type then
          acc // { ${stripNix name} = buildFn (dir + "/" + name) (stripNix name); }
        else acc
      )
      { }
      fs;

  # ------------------------------------------------------------------------
  # wirePackages: Collect .nix files or dirs with default.nix from a packages
  # directory and call pkgs.callPackage on them
  # ------------------------------------------------------------------------
  wirePackages = { pkgs, dir, callFn ? pkgs.callPackage }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: callFn path { };
    };

  # ------------------------------------------------------------------------
  # mkUsers: Generic user collector
  #
  # Parameters:
  #   - hostDir: base directory (e.g., ./darwin)
  #   - hostname: name of the host (e.g., macbook)
  #   - userBuildFn: function (path: username: value)
  #
  # Returns:
  #   { username = userBuildFn path username; … }
  # ------------------------------------------------------------------------
  mkUsers = hostDir: hostname: userBuildFn:
    let
      usersDir = hostDir + "/" + hostname + "/users";
    in
    wireGeneric {
      dir = usersDir;
      buildFn = path: username: userBuildFn path username;
    };

  # ------------------------------------------------------------------------
  # Specializations
  # ------------------------------------------------------------------------

  # Create user home directory configurations
  getUsers = hostDir: hostname: pkgs:
    mkUsers hostDir hostname (_path: username: {
      home = lib.mkDefault
        "/${if pkgs.stdenv.isDarwin then "Users" else "home"}/${username}";
    });

  # Create Home Manager user configurations
  getUsersHome = hostDir: hostname:
    mkUsers hostDir hostname (path: _username: {
      imports = [ path ];
    });

  # ------------------------------------------------------------------------
  # wireModules: Collect modules from a directory
  # Uses wireGeneric and returns an attrset mapping each modulename to its path
  # ------------------------------------------------------------------------
  wireModules = { dir }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: path;
    };


  # ------------------------------------------------------------------------
  # wireOverlays: Collect overlays from a overlays directory
  # imports each overlay with inputs and flake = inputs.self
  # ------------------------------------------------------------------------
  wireOverlays = { dir }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: import path commonSpecialArgs;
    };

  # ------------------------------------------------------------------------
  # wireTemplates: Collect flake templates from a directory
  # Each subdirectory becomes a template available via `nix flake init -t .#<name>`
  #
  # Parameters:
  #   - dir: directory containing template directories
  #
  # Each template directory can optionally contain a `template.nix` file
  # with { description = "..."; } for the template description.
  # If no template.nix exists, the directory name is used as description.
  # ------------------------------------------------------------------------
  wireTemplates = { dir }:
    wireGeneric {
      inherit dir;
      # Accept any directory as a template — template.nix is optional metadata only
      isDirAccepted = name: type: _dir: type == "directory";
      buildFn = path: name:
        let
          metaFile = path + "/template.nix";
          meta =
            if builtins.pathExists metaFile
            then import metaFile
            else { description = "${name} template"; };
        in
        {
          path = path;
          inherit (meta) description;
        };
    };

  # ------------------------------------------------------------------------
  # mkDarwinConfigs: Collect Darwin host configurations
  # Uses wireGeneric and wraps each config with nix-darwin.lib.darwinSystem
  # ------------------------------------------------------------------------
  mkDarwinConfigs = { dir, home }:
    let
      nix-darwin = inputs.nix-darwin
        or (throw "nix-wire uses nix-darwin but it is not available in inputs");
    in
    wireGeneric {
      inherit dir;
      buildFn = path: name: nix-darwin.lib.darwinSystem {
        specialArgs = commonSpecialArgs;
        modules = (commonModules "darwin" home path dir name) ++ [
          {
            networking.hostName = lib.mkDefault name;
          }
        ];
      };
    };

  # ------------------------------------------------------------------------
  # mkNixosConfigs: Collect NixOS host configurations
  # Uses wireGeneric and wraps each config with nixpkgs.lib.nixosSystem
  # ------------------------------------------------------------------------
  mkNixosConfigs = { dir, home }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: inputs.nixpkgs.lib.nixosSystem {
        specialArgs = commonSpecialArgs;
        modules = (commonModules "nixos" home path dir name) ++ [
          { networking.hostName = lib.mkDefault name; }
        ];
      };
    };

  # ------------------------------------------------------------------------
  # mkIsoConfigs: Collect NixOS ISO configurations
  # Works like mkNixosConfigs but auto-imports the installation-cd-minimal profile,
  # so ISO hosts get the same home-manager wiring as regular NixOS hosts.
  #
  # Parameters:
  #   - dir: directory containing ISO host configs
  #   - home: boolean, whether to include home-manager modules
  #   - installerModule: which installer profile to import
  #     (default: "installation-cd-minimal.nix")
  # ------------------------------------------------------------------------
  mkIsoConfigs = { dir, home ? true, installerModule ? "installation-cd-minimal.nix" }:
    wireGeneric {
      inherit dir;
      buildFn = path: name: inputs.nixpkgs.lib.nixosSystem {
        specialArgs = commonSpecialArgs;
        modules = (commonModules "nixos" home path dir name) ++ [
          ({ modulesPath, ... }: {
            imports = [ "${modulesPath}/installer/cd-dvd/${installerModule}" ];
          })
          { networking.hostName = lib.mkDefault name; }
        ];
      };
    };

  # ------------------------------------------------------------------------
  # mkHomeConfigs: Collect Home Manager user configurations
  # Uses wireGeneric and wraps each config with home-manager.lib.homeManagerConfiguration
  #
  # Parameters:
  #   - dir: directory containing user configuration files
  #   - pkgs: nixpkgs instance used for homeDirectory path resolution
  # ------------------------------------------------------------------------
  mkHomeConfigs = { dir, pkgs }:
    let
      hmInput =
        inputs.home-manager
          or (throw "nix-wire uses home-manager but it is not available in inputs");
    in
    wireGeneric {
      inherit dir;
      buildFn = path: username:
        hmInput.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs; flake = inputs.self; };
          modules = [
            path
            {
              home = {
                username = username;
                homeDirectory = "/${if pkgs.stdenv.isDarwin then "Users" else "home"}/${username}";
              };
              nix.package = lib.mkDefault pkgs.nix;
            }
          ];
        };
    };

in
{
  inherit wirePackages mkDarwinConfigs mkNixosConfigs mkIsoConfigs mkHomeConfigs wireModules wireOverlays wireTemplates;
}
