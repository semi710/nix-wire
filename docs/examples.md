# Examples

Real examples from the `example/` directory in the nix-wire repository.

---

## Example flake

The `example/` directory contains a complete working flake that demonstrates
all of nix-wire's auto-wiring features.

### flake.nix

```nix
{
  inputs = {
    nix-wire.url = "path:../";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs: inputs.nix-wire.mkFlake {
    inherit inputs;
  };
}
```

### Directory structure

```text
example/
├── flake.nix
├── devshells/
│   └── default.nix                  # → devShells.<system>.default
├── hosts/
│   ├── nixos/
│   │   ├── laptop.nix                # → nixosConfigurations.laptop
│   │   └── workstation/
│   │       ├── default.nix           # → nixosConfigurations.workstation
│   │       └── users/
│   │           └── bob.nix          # → HM config for user "bob"
│   ├── darwin/
│   │   ├── macbook/
│   │   │   ├── default.nix           # → darwinConfigurations.macbook
│   │   │   └── users/
│   │   │       ├── carol/
│   │   │       │   └── default.nix   # → HM config for user "carol"
│   │   │       └── dave.nix          # → HM config for user "dave"
│   │   └── office-mac.nix            # → darwinConfigurations.office-mac
│   └── home/
│       └── alice.nix                 # → homeConfigurations.alice
├── modules/
│   ├── nixos/
│   │   └── test.nix                  # → nixosModules.test
│   ├── darwin/
│   │   └── test.nix                  # → darwinModules.test
│   ├── home/
│   │   └── test.nix                  # → homeModules.test
│   └── flake/
│       └── test.nix                  # → flakeModules.test
├── overlays/
│   └── default.nix                   # → overlays.default
└── packages/
    ├── bar.nix                       # → packages.<system>.bar
    └── foo/
        └── default.nix               # → packages.<system>.foo
```

---

## NixOS hosts

### Flat file: laptop.nix

```nix
# hosts/nixos/laptop.nix
{ ... }: {
  nixpkgs.hostPlatform = "aarch64-linux";
  system.stateVersion = "24.05";
}
```

This becomes `nixosConfigurations.laptop`.

### Directory with users: workstation/

```nix
# hosts/nixos/workstation/default.nix
{ ... }: {
  nixpkgs.hostPlatform = "aarch64-linux";
  system.stateVersion = "24.05";
}
```

```nix
# hosts/nixos/workstation/users/bob.nix
{ ... }: {
  home.stateVersion = "25.11";
}
```

nix-wire automatically:

1. Creates `nixosConfigurations.workstation`
2. Creates `users.users.bob` with `home = "/home/bob"`
3. Wires `home-manager.users.bob` to import `bob.nix`
4. Imports `home-manager.nixosModules.home-manager`

---

## Darwin hosts

### Directory with nested user dir: macbook/

```nix
# hosts/darwin/macbook/default.nix
{ flake, ... }: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 5;
}
```

```nix
# hosts/darwin/macbook/users/carol/default.nix
{ ... }: {
  home.stateVersion = "25.11";
}
```

```nix
# hosts/darwin/macbook/users/dave.nix
{ ... }: {
  home.stateVersion = "25.11";
}
```

!!! tip "Mixed user styles"
    The `macbook/` host shows both user styles working together:
    `carol/default.nix` (directory) and `dave.nix` (flat file). Both are
    auto-discovered and wired into Home Manager.

The `flake` argument is available because nix-wire passes
`{ inherit inputs; flake = inputs.self; }` as special args.

### Flat file: office-mac.nix

```nix
# hosts/darwin/office-mac.nix
{ ... }: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 5;
}
```

Becomes `darwinConfigurations.office-mac`.

---

## Standalone Home Manager

```nix
# hosts/home/alice.nix
{ ... }: {
  home.stateVersion = "25.11";
}
```

Becomes `legacyPackages.<system>.homeConfigurations.alice`. Use with:

```bash
home-manager switch --flake .#alice
```

---

## Packages

### Flat file: bar.nix

```nix
# packages/bar.nix
{ pkgs, ... }: pkgs.hello
```

Becomes `packages.<system>.bar`. This is a minimal package that just
re-exports `pkgs.hello`.

### Directory with default.nix: foo/

```nix
# packages/foo/default.nix
{ pkgs, ... }: pkgs.hello
```

Becomes `packages.<system>.foo`. Same result as `bar.nix`, just using the
directory form.

---

## Dev shells

```nix
# devshells/default.nix
{ pkgs, ... }:
pkgs.mkShell {
  shellHook = ''
    echo "Welcome to the development shell!"
  '';
}
```

Becomes `devShells.<system>.default`. Use with:

```bash
nix develop
# or
nix develop .#default
```

---

## Overlays

```nix
# overlays/default.nix
{ ... }:
final: prev: { }
```

Becomes `overlays.default`. The overlay receives `{ inputs, flake }` as
extra arguments before `final: prev:`. It's automatically applied to all
`pkgs` instances within the flake.

---

## Modules

All four module types work identically — the file is collected and its path
is exposed as a flake attribute.

```nix
# modules/nixos/test.nix
{ ... }: { }
```

```nix
# modules/darwin/test.nix
{ ... }: { }
```

```nix
# modules/home/test.nix
{ ... }: { }
```

```nix
# modules/flake/test.nix
{ ... }: { }
```

These become:

- `nixosModules.test`
- `darwinModules.test`
- `homeModules.test`
- `flakeModules.test`

Use them in host configs:

```nix
{ flake, ... }: {
  imports = [ flake.nixosModules.test ];
}
```
