# Key Decisions

Record of architectural decisions and their rationale. Update when making
new decisions.

## flake-parts as the foundation

**Decision:** Build on `flake-parts.lib.mkFlake` rather than raw `outputs`.

**Why:** flake-parts provides `perSystem` evaluation, module merging, and a
clean extension model. nix-wire is a thin wrapper that pre-wires the
auto-discovery — users still get all of flake-parts' features (additional
modules via `imports`, perSystem, etc.).

## wireGeneric as the single engine

**Decision:** One generic directory walker (`wireGeneric`) with a `buildFn`
parameter, rather than separate walkers for each use case.

**Why:** Every auto-wiring function (hosts, modules, packages, overlays,
templates) does the same thing: scan a directory, handle the
file-vs-directory precedence, and build an attrset. Only the `buildFn`
differs. One function, zero duplication. The `buildFn` receives both `path`
and `name` so specializations can use the entry name (e.g., hostname,
username, package name).

## Directory-over-file precedence

**Decision:** When both `foo.nix` and `foo/default.nix` exist, the
directory wins and the file is silently dropped (`filterPreferDir`).

**Why:** Lets users start with a flat file and upgrade to a directory (to
add `users/` or more files) without renaming or deleting. The directory is
the "richer" form and should take precedence. This only applies to
`wireGeneric` (used by mkFlake), not to `autoImport`/`autoImportExcept`
(which return lists for `imports` and don't apply precedence).

## ISOs as per-system packages, not flake-level configs

**Decision:** ISO images live in `packages.<system>.<name>` with the full
config attached as `passthru.config`, not in a separate
`isoConfigurations` flake attribute.

**Why:** `nix build .#rescue` should "just work" and produce a native-arch
ISO for the current machine. Per-system packages auto-resolve the bare
name. A separate flake-level attribute would require specifying the system.
The `passthru.config` trick makes the config inspectable without a separate
attribute, eliminating redundancy.

## autoImport/autoImportExcept as pure builtins

**Decision:** `autoImport` and `autoImportExcept` use only `builtins.*`
functions, not `nixpkgs.lib`.

**Why:** These are exported as `inputs.nix-wire.lib.*` for use in any
evaluation context — inside module files, in `nix repl`, with `nix eval
--impure`. They don't depend on nixpkgs being available in the evaluator.
`wireGeneric` (internal) does use `nixpkgs.lib` because it always runs
inside `mkFlake` where nixpkgs is available.

## commonSpecialArgs: inputs + flake

**Decision:** Pass `{ inherit inputs; flake = inputs.self; }` as special
args to every host, home-manager, and overlay config.

**Why:** Users need access to their flake inputs (other flakes, overlays,
modules) and a reference to `self` (to reference their own modules,
packages, etc.). The `flake` alias is shorter and reads better:
`flake.homeModules.shell` vs `inputs.self.homeModules.shell`.

## All defaults via mkDefault

**Decision:** Every automatic setting (`allowUnfree`,
`experimental-features`, `max-jobs`, `hostName`, home directory paths) uses
`lib.mkDefault`.

**Why:** Users should be able to override anything nix-wire sets without
fighting priority levels. `mkDefault` has the lowest priority, so any
explicit setting in the user's config wins. No surprises.

## Home Manager integration opt-in via `home` parameter

**Decision:** Home Manager is enabled by default (`home = true`) but can
be disabled with a single parameter.

**Why:** Most users want Home Manager. But some flakes (e.g., server-only,
CI-only) don't need it and shouldn't require `home-manager` in inputs. The
`home = false` flag skips the HM module import entirely while keeping user
discovery for `users.users`.

## Templates accept any directory

**Decision:** `wireTemplates` uses a custom `isDirAccepted` that accepts
any directory — no `default.nix` or `.nix` file required inside.

**Why:** Flake templates are project scaffolds — they contain arbitrary
files (`.envrc`, `flake.nix`, `.gitignore`, README, etc.), not Nix
modules. Requiring `default.nix` would be wrong. An optional `template.nix`
provides metadata (description) if desired.
