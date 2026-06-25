# Overlays

How overlays work with nix-wire.

---

## Directory layout

Overlays live under `overlays/` (hardcoded path - not configurable via
`mkFlake` parameters, but affected by `prefix`):

```text
overlays/
├── default.nix           # → overlays.default
├── python.nix            # → overlays.python
└── fonts/
    └── default.nix        # → overlays.fonts
```

Same file conventions as everything else - flat `.nix` file or directory
with `default.nix`.

## How wireOverlays works

```nix
wireOverlays = { dir }:
  wireGeneric {
    inherit dir;
    buildFn = path: name: import path commonSpecialArgs;
  };
```

Each overlay file is **imported** with `commonSpecialArgs`:

```nix
commonSpecialArgs = { inherit inputs; flake = inputs.self; };
```

This means your overlay function receives `inputs` and `flake` as arguments
**before** the `final: prev:` overlay function:

```nix
# overlays/my-overlay.nix
{ inputs, flake, ... }:        # ← these come from commonSpecialArgs
final: prev: {                  # ← standard overlay signature
  myPackage = prev.myPackage.override { ... };
}
```

## Automatic application

nix-wire applies all overlays to every `pkgs` instance in the flake:

```nix
# In mkFlake's perSystem:
_module.args.pkgs = import inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;
  overlays = lib.attrValues inputs.self.overlays;
};
```

This means **every package, devshell, and host** in your flake
automatically gets the overlaid `pkgs`. You don't need to manually apply
overlays anywhere.

## Example overlays

### Patching a package

```nix
# overlays/fix-hello.nix
{ ... }:
final: prev: {
  hello = prev.hello.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./hello-fix.patch ];
  });
}
```

### Overriding with a different version

```nix
# overlays/neovim-nightly.nix
{ inputs, ... }:
final: prev: {
  neovim = inputs.neovim-nightly-overlay.packages.${final.system}.default;
}
```

### Adding a custom package

```nix
# overlays/my-tools.nix
{ ... }:
final: prev: {
  my-script = final.writeShellScriptBin "my-script" ''
    echo "Hello from my-script"
  '';
}
```

### Empty overlay (placeholder)

```nix
# overlays/default.nix
{ ... }:
final: prev: { }
```

## Using overlays from inputs

Since `inputs` is available in the overlay function, you can pull overlays
from other flakes:

```nix
# overlays/emacs.nix
{ inputs, ... }:
final: prev: {
  emacs = inputs.emacs-overlay.packages.${final.system}.emacs;
  emacsPackagesFor = emacsPkg: inputs.emacs-overlay.overlays.default final prev emacsPkg;
}
```

## Overlays and packages

Overlays and the `packages/` directory both contribute to
`packages.<system>`, but they work differently:

| | `packages/` | `overlays/` |
|---|---|---|
| Mechanism | `pkgs.callPackage` | `final: prev:` function |
| Applied to | Only this flake's `packages` | All `pkgs` instances in the flake |
| Use case | New packages | Modifying existing packages |
| Receives | `{ pkgs, ... }` (callPackage args) | `{ inputs, flake }` + `final: prev:` |

!!! tip "When to use which"
    Use `packages/` for new standalone packages. Use `overlays/` when you
    need to modify existing nixpkgs packages or make a package available
    everywhere in the flake (including inside host configs).
