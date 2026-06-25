# Quickstart

Get nix-wire working in your flake in under five minutes.

---

## 1. Add nix-wire as a flake input

Add nix-wire and its dependencies to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-wire.url = "github:semi710/nix-wire";
  };
}
```

!!! note "Dependencies"
    - **flake-parts** is required - nix-wire is built on it.
    - **home-manager** is required if `home = true` (the default).
    - **nix-darwin** is required if you have `hosts/darwin/` entries.

## 2. Wire your outputs

Replace your `outputs` with a single call to `mkFlake`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-wire.url = "github:semi710/nix-wire";
  };

  outputs = inputs: inputs.nix-wire.mkFlake { inherit inputs; };
}
```

## 3. Create your directory structure

```text
.
├── flake.nix
├── hosts/
│   └── nixos/
│       └── myhost.nix        # → nixosConfigurations.myhost
├── packages/
│   └── mypkg.nix             # → packages.x86_64-linux.mypkg
└── modules/
    └── nixos/
        └── mymodule.nix      # → nixosModules.mymodule
```

## 4. Write a host config

```nix
# hosts/nixos/myhost.nix
{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "24.05";

  environment.systemPackages = with pkgs; [ vim git ];
}
```

## 5. Build it

```bash
# Build the NixOS configuration
nixos-rebuild switch --flake .#myhost

# Build a package
nix build .#mypkg

# Enter a devshell (if you have devshells/default.nix)
nix develop
```

---

## What you get automatically

With just the `mkFlake` call above, nix-wire provides:

- **`nixosConfigurations`** - from `hosts/nixos/`
- **`darwinConfigurations`** - from `hosts/darwin/`
- **`packages`** - from `packages/` (via `callPackage`)
- **`devShells`** - from `devshells/`
- **`nixosModules`**, **`darwinModules`**, **`homeModules`**, **`flakeModules`** - from `modules/`
- **`overlays`** - from `overlays/`
- **`templates`** - from `templates/`
- **`legacyPackages.homeConfigurations`** - standalone Home Manager from `hosts/home/`
- **ISO images** - from `hosts/iso/` as per-system packages

Every host automatically gets:

- Home Manager integration (if `home = true`)
- User discovery from `users/` subdirectory
- `allowUnfree`, `experimental-features`, `max-jobs` defaults
- `inputs` and `flake` (alias for `inputs.self`) in special args

---

## Adding per-user Home Manager configs

Create a `users/` directory inside any host:

```text
hosts/nixos/myhost/
├── default.nix          # System config
└── users/
    └── alice.nix        # Home config for "alice"
```

```nix
# hosts/nixos/myhost/users/alice.nix
{ flake, ... }:
{
  home.stateVersion = "25.11";
  imports = [
    flake.homeModules.shell    # If you have a shell module
  ];

  programs.git = {
    enable = true;
    userName = "Alice";
  };
}
```

nix-wire automatically:

1. Creates `users.users.alice` with `home = "/home/alice"`
2. Wires `home-manager.users.alice` to import `alice.nix`
3. Passes `inputs` and `flake` to the home config

---

## Customizing mkFlake

All directory names and behavior are configurable:

```nix
outputs = inputs: inputs.nix-wire.mkFlake {
  inherit inputs;
  # Override directory names
  packages = "pkgs";           # default: "packages"
  devShells = "shells";        # default: "devShells"
  hosts = "machines";          # default: "hosts"

  # Disable Home Manager integration
  home = false;

  # Limit supported systems
  systems = [ "x86_64-linux" "aarch64-linux" ];

  # Add flake-parts modules
  imports = [ ./my-flake-module.nix ];
};
```

See the [API reference](api.md#mkflake) for all parameters.

---

## Using autoImport in module files

nix-wire also exports `autoImport` and `autoImportExcept` for use outside
the main wiring - e.g., in a module file that wants to import its siblings:

```nix
# modules/nixos/default.nix
{ inputs, ... }:
{
  imports = inputs.nix-wire.lib.autoImport ./.;
}
```

Or with exclusions:

```nix
{ inputs, ... }:
{
  imports = inputs.nix-wire.lib.autoImportExcept ./. [ "default.nix" "special.nix" ];
}
```

These are **pure builtins** functions that work in any evaluation context.
