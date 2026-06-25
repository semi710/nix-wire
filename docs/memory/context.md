# LLM Context

This file maintains the current state of the nix-wire project for LLM
assistants. Update it when making significant changes.

## Goal

A lightweight Nix flake auto-wiring library that eliminates boilerplate by
discovering hosts, modules, packages, overlays, templates, and devshells
from directory structure. Built on flake-parts. Used by the ndots
configuration.

## Constraints & Preferences

- **Ponytail mode** (lazy senior dev) — minimal code, no over-engineering
- No clutter comments (no `---` dividers, no ASCII art), comments explain why not what
- Pure builtins for `autoImport`/`autoImportExcept` (must work in any eval context)
- All defaults via `mkDefault` — overridable by users
- Single entry point: `mkFlake` — wraps `flake-parts.lib.mkFlake`
- Convention over configuration — sensible defaults, every directory name overridable
- MIT license

## Current State

### Done
- `mkFlake` entry point in `lib/default.nix` with all auto-wiring
- `wireGeneric` engine in `lib/utils.nix` — generic directory walker
- All specializations: `mkNixosConfigs`, `mkDarwinConfigs`, `mkIsoPackages`,
  `mkHomeConfigs`, `wireModules`, `wireOverlays`, `wirePackages`,
  `wireTemplates`
- `autoImport` and `autoImportExcept` — pure builtins utilities, exported
  as `inputs.nix-wire.lib.*`
- Per-user Home Manager auto-discovery via `users/` subdirectory
- ISO support — arch-aware, per-system packages with `passthru.config`
- Template support — any directory under `templates/` becomes a template
- Example flake in `example/` demonstrating all features
- Dev environment in `dev/` with flake-parts + git-hooks
- Docs site (MkDocs Material, GitHub Pages, nix-wire.semi.sh)

### Deferred
- Better template / test structure (README TODO)
- CI with checks (formatting, evaluation) (README TODO)
- `nix flake check` integration (README TODO)

## Key Gotchas

- `autoImport` does NOT apply the directory-over-file precedence rule
  (unlike `wireGeneric`). Both `foo.nix` and `foo/` are returned. Use
  `autoImportExcept` to exclude duplicates.
- `installerModule` in `mkIsoPackages` is a global setting — applies to all
  ISOs in `hosts/iso/`. No per-ISO override without customizing mkFlake.
- ISOs must NOT set `nixpkgs.hostPlatform` — nix-wire derives it from the
  build system for arch-aware evaluation.
- `modules/` directory name is hardcoded (not configurable via mkFlake
  params). Only `prefix` changes the base path.
- `overlays/` directory name is also hardcoded — same as `modules/`.
- Home Manager and nix-darwin are required only if you have corresponding
  hosts. flake-parts is always required.
- The `lib` attribute on the flake only exports `autoImport` and
  `autoImportExcept` — the other functions are internal.
