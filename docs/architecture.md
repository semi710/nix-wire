# Architecture

How nix-wire auto-wires your flake outputs from directory structure.

---

## Overview

nix-wire is a thin layer over [flake-parts](https://flake.parts/). The entry
point is `mkFlake` (in `lib/default.nix`), which calls
`flake-parts.lib.mkFlake` with a pre-wired configuration that scans your
project directories and generates the appropriate flake attributes.

The core engine is the **`wireGeneric`** function (in `lib/utils.nix`) — a
generic directory walker that collects `.nix` files and directories with
`default.nix` into an attribute set. Every auto-wiring function is a
specialization of `wireGeneric` with a different `buildFn`.

```
mkFlake (lib/default.nix)
  └─ flake-parts.lib.mkFlake
       ├─ flake.nixosConfigurations   ← mkNixosConfigs    ← wireGeneric
       ├─ flake.darwinConfigurations  ← mkDarwinConfigs   ← wireGeneric
       ├─ flake.nixosModules          ← wireModules       ← wireGeneric
       ├─ flake.darwinModules         ← wireModules       ← wireGeneric
       ├─ flake.homeModules           ← wireModules       ← wireGeneric
       ├─ flake.flakeModules          ← wireModules       ← wireGeneric
       ├─ flake.overlays              ← wireOverlays      ← wireGeneric
       ├─ flake.templates             ← wireTemplates      ← wireGeneric
       └─ perSystem:
            ├─ packages               ← wirePackages      ← wireGeneric
            │                         ← mkIsoPackages     ← wireGeneric
            ├─ devShells              ← wirePackages      ← wireGeneric
            └─ legacyPackages.homeConfigurations ← mkHomeConfigs ← wireGeneric
```

---

## wireGeneric — the engine

```nix
wireGeneric = { dir, buildFn, isDirAccepted ? isDirWithDefault }:
```

This is the heart of nix-wire. It scans a directory and builds an attribute
set from what it finds:

1. **Reads the directory** safely (returns `{}` if it doesn't exist)
2. **Applies the precedence rule** — if both `foo.nix` and `foo/default.nix`
   exist, `foo.nix` is filtered out and `foo/default.nix` wins
3. **Iterates** over every entry:
   - If it's a directory with `default.nix` (or matches `isDirAccepted`):
     adds `{ ${name} = buildFn (dir/name) name; }`
   - If it's a `.nix` file: adds `{ ${stripNix name} = buildFn (dir/name) (stripNix name); }`
   - Otherwise: skips it
4. **Returns** the merged attribute set

The `buildFn` receives two arguments: the **path** to the file (or
`default.nix`) and the **name** (entry name without `.nix`, or directory
name). This lets each specialization know what it's processing — e.g.,
hostnames, package names, usernames.

### Precedence: directory over file

The `filterPreferDir` function ensures that when both `foo.nix` and
`foo/default.nix` exist in the same directory, `foo/default.nix` is used and
`foo.nix` is silently dropped. This lets you start with a flat file and
upgrade to a directory later without renaming.

---

## mkNixosConfigs

```nix
mkNixosConfigs = { dir, home }:
```

Scans `hosts/nixos/` and creates `nixosConfigurations.<hostname>` for each
entry. For every host, it assembles a module list:

```
modules = commonModules("nixos", home, path, dir, hostname)
        ++ [{ networking.hostName = mkDefault hostname; }]
```

### commonModules breakdown

`commonModules` builds the shared module list for every NixOS/Darwin host:

```nix
commonModules = type: home: path: dir: hostname:
  [
    path                              # ← the host's own config file
    ({ pkgs, ... }: {
      imports = homeModules;          # ← home-manager modules (if home=true)
      users.users = getUsers dir hostname pkgs;  # ← auto-discovered users
    })
    commonNix                         # ← allowUnfree, experimental-features, etc.
  ]
```

When `home = true`, `homeModules` expands to `commonHomeModules`, which:

1. Imports `home-manager.nixosModules.home-manager`
2. Sets `useGlobalPkgs`, `useUserPackages`, `backupFileExtension` (all `mkDefault`)
3. Wires `home-manager.users` from the host's `users/` subdirectory via `getUsersHome`
4. Sets `extraSpecialArgs` to `{ inherit inputs; flake = inputs.self; }`
5. Adds `sharedModules` with Darwin-specific `sessionPath` on macOS

---

## mkDarwinConfigs

```nix
mkDarwinConfigs = { dir, home }:
```

Identical to `mkNixosConfigs` but wraps with `nix-darwin.lib.darwinSystem`
instead of `nixpkgs.lib.nixosSystem`. Uses `home-manager.darwinModules.home-manager`
for Home Manager integration.

---

## mkIsoPackages

```nix
mkIsoPackages = { dir, home ? true, system, installerModule ? "installation-cd-minimal.nix" }:
```

Builds ISO image derivations as per-system packages. Key design choices:

1. **Arch-aware** — only evaluates on `-linux` systems (Darwin builds are
   skipped via `lib.optionalAttrs`)
2. **Per-system, not flake-level** — ISOs live in `packages.<system>.<name>`,
   not in a separate `isoConfigurations` attribute. This means `nix build .#rescue`
   automatically produces a native-arch ISO for the current machine.
3. **Inspectable** — the full NixOS evaluation is attached as `passthru.config`,
   so `nix eval .#packages.x86_64-linux.rescue --apply 'x: x.passthru.config...'`
   works without a separate flake attribute.
4. **Installer profile** — automatically imports `installation-cd-minimal.nix`
   from nixpkgs' `modulesPath`, giving you a bootable ISO. Override with
   `installerModule` to use a different profile.

The module assembly uses `isoModules`, a DRY helper:

```nix
isoModules = home: path: dir: name: installerModule:
  commonModules("nixos", home, path, dir, name)
  ++ [ ({ modulesPath, ... }: {
       imports = [ "${modulesPath}/installer/cd-dvd/${installerModule}" ];
     })
     { networking.hostName = mkDefault name; }
  ]
```

---

## mkHomeConfigs

```nix
mkHomeConfigs = { dir, pkgs }:
```

Scans `hosts/home/` for **standalone** Home Manager configurations — users
not tied to a specific NixOS/Darwin host. Each entry becomes a
`homeManagerConfiguration` with:

- `username` and `homeDirectory` set automatically from the filename
- `homeDirectory` resolves to `/Users/<name>` on Darwin, `/home/<name>` on Linux
- `nix.package` set to `pkgs.nix`
- `extraSpecialArgs` with `inputs` and `flake`

Results land in `legacyPackages.homeConfigurations` (per-system, since `pkgs`
varies by platform).

---

## wireModules

```nix
wireModules = { dir }:
```

The simplest specialization — `buildFn` just returns the path itself. Scans
`modules/nixos/`, `modules/darwin/`, `modules/home/`, `modules/flake/` and
maps each entry name to its file path. These become `nixosModules`,
`darwinModules`, `homeModules`, and `flakeModules` respectively.

---

## wireOverlays

```nix
wireOverlays = { dir }:
```

Scans `overlays/` and imports each overlay with `commonSpecialArgs`
(`{ inherit inputs; flake = inputs.self; }`). The imported overlay function
receives these args in addition to `final: prev`.

---

## wirePackages

```nix
wirePackages = { pkgs, dir, callFn ? pkgs.callPackage }:
```

Scans a packages (or devshells) directory and applies `pkgs.callPackage` to
each entry. Used for both `packages/` → `packages` and `devshells/` →
`devShells`.

---

## wireTemplates

```nix
wireTemplates = { dir }:
```

Scans `templates/` and maps each subdirectory to a template object
`{ path = ...; description = ...; }`. Uses a custom `isDirAccepted` that
accepts **any** directory (not just those with `default.nix`). An optional
`template.nix` inside the directory provides `{ description = "..."; }`;
otherwise the directory name is used as the description.

---

## User discovery

### mkUsers

```nix
mkUsers = hostDir: hostname: userBuildFn:
```

Generic user collector. Looks for `users/` inside a host directory and walks
it with `wireGeneric`. Each user file/directory becomes an entry.

### getUsers

```nix
getUsers = hostDir: hostname: pkgs:
```

Creates `users.users.<name>` entries with a default `home` path:
`/Users/<name>` on Darwin, `/home/<name>` on Linux.

### getUsersHome

```nix
getUsersHome = hostDir: hostname:
```

Creates `home-manager.users.<name>` entries that import each user's config
file. This is what wires per-user Home Manager configs into hosts.

---

## Special args

Every host module and Home Manager module receives:

```nix
commonSpecialArgs = { inherit inputs; flake = inputs.self; };
```

- **`inputs`** — your full flake inputs attrset
- **`flake`** — alias for `inputs.self` (so you can write `flake.homeModules.shell`)

---

## Common Nix settings

All hosts get these defaults (all via `mkDefault`, so you can override):

```nix
commonNix = {
  nixpkgs.config.allowUnfree = mkDefault true;
  nixpkgs.overlays = attrValues inputs.self.overlays;
  nix.settings.max-jobs = mkDefault "auto";
  nix.settings.experimental-features = mkDefault "nix-command flakes";
};
```

---

## autoImport and autoImportExcept

```nix
autoImport = dir:
autoImportExcept = dir: exclusions:
```

These are **pure builtins** utilities — they work in any evaluation context
(flakes, modules, repl). They return a **list of paths** (not an attrset),
suitable for use in `imports` lists.

- `autoImport` — imports all sibling `.nix` files and dirs with `default.nix`
  (skips `default.nix` itself)
- `autoImportExcept` — same, but also skips names in the exclusions list

These are exported from the flake as `inputs.nix-wire.lib.autoImport` and
`inputs.nix-wire.lib.autoImportExcept` for use **outside** of the `mkFlake`
wiring — e.g., in module files where you want to auto-import siblings.
