# Adding Modules

How module auto-import works in nix-wire.

---

## Directory layout

Modules live under `modules/` with four subdirectories:

```text
modules/
├── nixos/     # → nixosModules
├── darwin/    # → darwinModules
├── home/      # → homeModules
└── flake/     # → flakeModules
```

Each subdirectory is scanned independently, and every `.nix` file or
directory with `default.nix` becomes a module in the corresponding flake
attribute.

## File styles

Same convention as hosts — flat file or directory:

```text
modules/nixos/
├── shell.nix               # → nixosModules.shell
├── fonts/
│   └── default.nix          # → nixosModules.fonts
└── networking/
    └── default.nix          # → nixosModules.networking
```

## What wireModules does

```nix
wireModules = { dir }:
  wireGeneric {
    inherit dir;
    buildFn = path: name: path;
  };
```

The simplest specialization — `buildFn` just returns the path. The result
is an attrset mapping names to paths:

```nix
nixosModules = {
  shell = ./modules/nixos/shell.nix;
  fonts = ./modules/nixos/fonts;
  networking = ./modules/nixos/networking;
}
```

## Using modules in hosts

Modules are available via `flake` (alias for `inputs.self`) in special args:

```nix
# hosts/nixos/myhost/default.nix
{ flake, ... }:
{
  imports = [
    flake.nixosModules.shell
    flake.nixosModules.fonts
  ];
}
```

```nix
# hosts/darwin/macbook/users/carol/default.nix
{ flake, ... }:
{
  imports = [
    flake.homeModules.shell
    flake.homeModules.editor
  ];
}
```

## Module types

### NixOS modules (`modules/nixos/`)

Standard NixOS modules. Receive `{ pkgs, lib, config, options, ... }` plus
the special args `{ inputs, flake }`.

```nix
# modules/nixos/shell.nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ zsh fzf starship ];

  programs.zsh.enable = true;
}
```

### Darwin modules (`modules/darwin/`)

nix-darwin modules. Same interface as NixOS modules but for macOS.

```nix
# modules/darwin/brew.nix
{ ... }:
{
  homebrew = {
    enable = true;
    brews = [ "ripgrep" ];
  };
}
```

### Home Manager modules (`modules/home/`)

Home Manager modules for per-user configs. Receive `{ pkgs, config, ... }`
plus special args.

```nix
# modules/home/shell.nix
{ pkgs, ... }:
{
  programs.zsh.enable = true;
  programs.starship.enable = true;

  home.packages = with pkgs; [ fzf bat eza ];
}
```

### Flake modules (`modules/flake/`)

flake-parts modules. These are imported into the flake-parts `mkFlake`
call. Use for flake-level configuration (pre-commit, treefmt, CI, etc.).

```nix
# modules/flake/treefmt.nix
{ ... }:
{
  perSystem = { pkgs, ... }: {
    treefmt = {
      enable = true;
      programs.nixpkgs-fmt.enable = true;
    };
  };
}
```

!!! note "Flake modules and imports"
    Flake modules from `modules/flake/` are available as
    `flakeModules.<name>` but are **not** automatically imported. To use
    them, pass them via the `imports` parameter:

    ```nix
    outputs = inputs: inputs.nix-wire.mkFlake {
      inherit inputs;
      imports = [ inputs.self.flakeModules.treefmt ];
    };
    ```

    Or import directly:

    ```nix
    outputs = inputs: inputs.nix-wire.mkFlake {
      inherit inputs;
      imports = [ ./modules/flake/treefmt.nix ];
    };
    ```

---

## Custom module directory

There's no parameter to change the `modules/` directory name — it's
hardcoded as `${prefix}/modules/<type>/`. But you can change `prefix`:

```nix
outputs = inputs: inputs.nix-wire.mkFlake {
  inherit inputs;
  prefix = ./config;  # Now looks for config/modules/nixos/, etc.
};
```
