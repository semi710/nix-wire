{ inputs, lib ? import <nixpkgs/lib>, ... }:

let
  # --- pure builtins helpers (work in any evaluation context) ---
  _attrNames = builtins.attrNames;
  _filter = builtins.filter;
  _hasSuffix = suffix: str:
    let
      suffixLen = builtins.stringLength suffix;
      strLen = builtins.stringLength str;
    in
    strLen >= suffixLen && builtins.substring (strLen - suffixLen) suffixLen str == suffix;
  _elem = x: xs: builtins.any (y: y == x) xs;
  _pathExists = builtins.pathExists;
  _readDir = builtins.readDir;

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
  # autoImport: Import all sibling .nix files and dirs with default.nix
  #
  # Pure builtins only — works in any evaluation context (flakes, modules, repl).
  # Handles both:
  #   - foo.nix (regular .nix file)
  #   - bar/    (directory containing default.nix)
  #
  # Usage: imports = inputs.nix-wire.lib.autoImport ./.;
  # ------------------------------------------------------------------------
  autoImport = dir:
    let
      entries = if _pathExists dir then _readDir dir else { };
      names = _attrNames entries;
      keep = name:
        let type = entries.${name};
        in
        (type == "regular" && name != "default.nix" && _hasSuffix ".nix" name)
        || (type == "directory" && _pathExists (dir + "/${name}/default.nix"));
    in
    map (name: dir + "/${name}") (_filter keep names);

  # ------------------------------------------------------------------------
  # autoImportExcept: Import siblings, skipping additional exclusions
  #
  # Same as autoImport but also excludes extra files/directories.
  #
  # Usage: imports = inputs.nix-wire.lib.autoImportExcept ./. ["combined-system-prompt.nix"];
  # ------------------------------------------------------------------------
  autoImportExcept = dir: exclusions:
    let
      skip = [ "default.nix" ] ++ exclusions;
      entries = if _pathExists dir then _readDir dir else { };
      names = _attrNames entries;
      keep = name:
        let type = entries.${name};
        in
        (type == "regular" && _hasSuffix ".nix" name && !(_elem name skip))
        || (type == "directory" && _pathExists (dir + "/${name}/default.nix") && !(_elem name skip));
    in
    map (name: dir + "/${name}") (_filter keep names);

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
  # isoModules: Shared module list for ISO hosts.
  # Used by mkIsoPackages to assemble the nixosSystem modules (DRY).
  # ------------------------------------------------------------------------
  isoModules = home: path: dir: name: installerModule:
    (commonModules "nixos" home path dir name) ++ [
      ({ modulesPath, ... }: {
        imports = [ "${modulesPath}/installer/cd-dvd/${installerModule}" ];
      })
      { networking.hostName = lib.mkDefault name; }
    ];

  # ------------------------------------------------------------------------
  # mkIsoPackages: Build ISO image derivations per-system (arch-aware)
  #
  # Returns the actual .iso image derivations scoped to each system's
  # architecture via perSystem. This lets `nix build .#<name>` produce a
  # native ISO for the build machine's current architecture.
  #
  # The full NixOS evaluation is attached as `passthru.config` so the package
  # is BOTH buildable (`nix build .#iso`) AND inspectable
  # (`nix eval .#packages.<system>.iso.passthru.config.<option>`).
  # This removes the need for a separate flake-level isoConfigurations.
  #
  # Only evaluates on Linux systems (ISOs are NixOS-specific).
  # ------------------------------------------------------------------------
  mkIsoPackages = { dir, home ? true, system, installerModule ? "installation-cd-minimal.nix" }:
    lib.optionalAttrs (lib.hasSuffix "-linux" system) (
      wireGeneric {
        inherit dir;
        buildFn = path: name:
          let
            eval = inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = commonSpecialArgs;
              modules = isoModules home path dir name installerModule;
            };
            iso = eval.config.system.build.isoImage;
          in
          iso // {
            passthru = (iso.passthru or { }) // { config = eval.config; };
          };
      }
    );

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
  inherit
    wirePackages
    mkDarwinConfigs
    mkNixosConfigs
    mkIsoPackages
    mkHomeConfigs
    wireModules
    wireOverlays
    wireTemplates
    autoImport
    autoImportExcept
    ;
}
