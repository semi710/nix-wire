# autoImportExcept

When and how to use `autoImport` and `autoImportExcept` outside of the
main `mkFlake` wiring.

---

## What they are

`autoImport` and `autoImportExcept` are **pure builtins** utilities
exported from the nix-wire flake:

```nix
inputs.nix-wire.lib.autoImport         # path -> [path]
inputs.nix-wire.lib.autoImportExcept   # path -> [string] -> [path]
```

They return a **list of paths** (not an attrset), designed for use in
`imports` lists. Unlike `wireGeneric` (used internally by `mkFlake`), these
work in any evaluation context — flakes, modules, `nix repl`, `nix eval`.

## When to use them

The main `mkFlake` wiring handles hosts, modules, packages, and overlays
automatically. But sometimes you need to auto-import files **inside** a
module or config — for example:

- A NixOS module that imports all its sibling module files
- A directory of service configs that should all be imported
- A user config that imports multiple sub-configs

## autoImport

```nix
autoImport : path -> [path]
```

Scans a directory and returns paths to all sibling `.nix` files and
directories with `default.nix`. Skips `default.nix` itself.

### Example

```nix
# modules/nixos/services/default.nix
{ inputs, ... }:
{
  imports = inputs.nix-wire.lib.autoImport ./.;
}
```

```text
modules/nixos/services/
├── default.nix      # ← this file (skipped)
├── ssh.nix           # ← imported
├── nginx/
│   └── default.nix   # ← imported
└── docker.nix        # ← imported
```

Result: `imports = [ ./ssh.nix ./nginx ./docker.nix ]`

## autoImportExcept

```nix
autoImportExcept : path -> [string] -> [path]
```

Same as `autoImport`, but also skips entries matching the exclusions list.

### Example: exclude a file

```nix
{ inputs, ... }:
{
  imports = inputs.nix-wire.lib.autoImportExcept ./. [ "experimental.nix" ];
}
```

### Example: exclude a directory

```nix
{ inputs, ... }:
{
  imports = inputs.nix-wire.lib.autoImportExcept ./. [ "wip" ];
  # If wip/default.nix exists, the wip directory is skipped
}
```

### Example: exclude multiple entries

```nix
{ inputs, ... }:
{
  imports = inputs.nix-wire.lib.autoImportExcept ./. [
    "experimental.nix"
    "wip"
    "disabled.nix"
  ];
}
```

---

## Difference from wireGeneric

| Feature | `autoImport` / `autoImportExcept` | `wireGeneric` (internal) |
|---|---|---|
| Returns | List of paths | Attrset `{ name = value; }` |
| Precedence rule | No — both `foo.nix` and `foo/` included | Yes — `foo/default.nix` wins over `foo.nix` |
| Context | Any (pure builtins) | Requires nixpkgs `lib` |
| Use case | `imports` lists in modules | Building flake attributes |
| Skips `default.nix` | Yes | Yes |

!!! warning "No precedence in autoImport"
    `autoImport` does **not** apply the directory-over-file precedence rule.
    If both `foo.nix` and `foo/default.nix` exist, **both** are returned in
    the list. This would cause a duplicate module error. Use
    `autoImportExcept` to exclude one:

    ```nix
    imports = inputs.nix-wire.lib.autoImportExcept ./. [ "foo.nix" ];
    # Now only foo/ (with default.nix) is imported
    ```

---

## Real-world pattern: auto-importing services

A common pattern is a "services" module that imports all service configs
in a directory:

```nix
# modules/nixos/services/default.nix
{ inputs, ... }:
{
  imports = inputs.nix-wire.lib.autoImport ./.;
}
```

Then in your host:

```nix
# hosts/nixos/myhost.nix
{ flake, ... }:
{
  imports = [ flake.nixosModules.services ];
}
```

This way, adding a new service is just dropping a `.nix` file in the
`services/` directory — no manual import list to maintain.
