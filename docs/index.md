# nix-wire

**A lightweight Nix flake auto-wiring library.**

Drop your configs into the right directories - nix-wire builds the flake
outputs for you. No manual imports, no boilerplate, no per-host wiring.

---

## What it does

nix-wire scans your project directory structure and automatically generates
flake attributes from what it finds:

| Directory | Flake Attribute | What it becomes |
|---|---|---|
| `hosts/nixos/` | `nixosConfigurations` | NixOS system configurations |
| `hosts/darwin/` | `darwinConfigurations` | macOS (nix-darwin) system configurations |
| `hosts/iso/` | `packages.<system>.<name>` | NixOS ISO images (arch-aware) |
| `hosts/home/` | `legacyPackages.homeConfigurations` | Standalone Home Manager users |
| `packages/` | `packages` | Custom packages (via `callPackage`) |
| `devshells/` | `devShells` | Development shells |
| `templates/` | `templates` | Flake templates (`nix flake init -t`) |
| `modules/nixos/` | `nixosModules` | NixOS modules |
| `modules/darwin/` | `darwinModules` | Darwin modules |
| `modules/home/` | `homeModules` | Home Manager modules |
| `modules/flake/` | `flakeModules` | Flake-parts modules |
| `overlays/` | `overlays` | Nixpkgs overlays |

## Why it exists

Every Nix flake that manages multiple hosts, users, packages, and modules
ends up with the same boilerplate: import this file, callPackage that
directory, wire home-manager into each host, pass specialArgs everywhere.

nix-wire eliminates that. You define a **convention** (directory names),
and the library walks the tree and assembles the flake outputs.

!!! note "Design philosophy"
    nix-wire intentionally keeps things **bare minimum**. It wires
    configurations - it doesn't impose a module system, a secrets framework,
    or an opinion on how you structure your configs. Similar projects like
    [blueprint](https://github.com/numtide/blueprint) exist; nix-wire focuses
    solely on wiring without additional complexity.

## One-line wiring

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

That's the entire `flake.nix`. Everything else is discovered from the
directory tree.

## Features

- **Auto-discovery** - hosts, modules, packages, overlays, templates, devshells
- **Home Manager integration** - per-user configs wired into each host automatically
- **User discovery** - `users/` subdirectory under each host creates user entries
- **ISO support** - build bootable NixOS ISOs as per-system packages
- **Standalone Home Manager** - `hosts/home/` for users not tied to a host
- **Template support** - `templates/` directory auto-discovered for `nix flake init -t`
- **Convention over configuration** - sensible defaults, every directory name overridable
- **Special args** - `inputs` and `flake` (alias for `inputs.self`) passed everywhere

## Built on flake-parts

nix-wire uses [flake-parts](https://flake.parts/) under the hood. The `mkFlake`
function is a thin wrapper around `flake-parts.lib.mkFlake` that pre-wires all
the auto-discovery logic. You can still pass additional flake-parts modules
via the `imports` parameter.

---

## Real-world usage

See [ndots](https://ndots.semi.sh) <a href="https://github.com/semi710/ndots" target="_blank">:fontawesome-brands-github:</a> for a complete NixOS + nix-darwin
configuration built with nix-wire - 5 hosts, 11 NixOS modules, shared
workstation configs, Home Manager users, custom packages, and ISO builds. The
entire `flake.nix` is just `inputs.nix-wire.mkFlake { inherit inputs; }`.

!!! example
    ndots uses nix-wire to auto-discover hosts (`obox`, `semi`, `dsd`, `mach`,
    `jp-mbp`), modules, packages, and overlays from the directory tree - zero
    manual wiring. Browse the
    [repo](https://github.com/semi710/ndots) to see
    the full structure.

## Docs

Docs are served at [nix-wire.semi.sh](https://nix-wire.semi.sh). To preview locally:

```bash
just doc
```
