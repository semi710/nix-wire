# nix-wire

**nix-wire** is a lightweight utility for structuring and wiring Nix flakes.
Instead of manually importing every `.nix` file, nix-wire walks your project directories and automatically generates the right flake attributes.

It discovers and assembles configurations for:

| Directory | Flake Attribute | Description |
|---|---|---|
| `hosts/nixos/` | `nixosConfigurations` | NixOS host systems |
| `hosts/darwin/` | `darwinConfigurations` | macOS (nix-darwin) host systems |
| `hosts/iso/` | `isoConfigurations` | NixOS ISO images (installer/live) |
| `hosts/home/` | `legacyPackages.homeConfigurations` | Standalone Home Manager users |
| `packages/` | `packages` | Custom packages |
| `devshells/` | `devShells` | Development shells |
| `templates/` | `templates` | Flake templates (`nix flake init -t`) |
| `modules/nixos/` | `nixosModules` | NixOS modules |
| `modules/darwin/` | `darwinModules` | Darwin modules |
| `modules/home/` | `homeModules` | Home Manager modules |
| `modules/flake/` | `flakeModules` | Flake-parts modules |
| `overlays/` | `overlays` | Nixpkgs overlays |

---

## Quick start

```nix
# flake.nix
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

That's it. Drop your configs into the right directories and nix-wire wires them up.

---

## Directory structure

```text
.
├── hosts
│   ├── nixos/                  # → nixosConfigurations
│   │   ├── workstation/
│   │   │   ├── users/
│   │   │   │   └── bob.nix     # Home config for user "bob"
│   │   │   └── default.nix     # System config for "workstation"
│   │   └── laptop.nix          # System config for "laptop"
│   │
│   ├── darwin/                 # → darwinConfigurations
│   │   ├── macbook/
│   │   │   ├── users/
│   │   │   │   ├── carol/
│   │   │   │   │   └── default.nix
│   │   │   │   └── dave.nix
│   │   │   └── default.nix
│   │   └── office-mac.nix
│   │
│   ├── iso/                    # → isoConfigurations
│   │   └── rescue/
│   │       ├── users/
│   │       │   └── nixos.nix   # Home config for "nixos" user on ISO
│   │       └── default.nix     # ISO system config for "rescue"
│   │
│   └── home/                   # → homeConfigurations (standalone)
│       └── alice.nix
│
├── modules/
│   ├── nixos/                  # → nixosModules
│   ├── darwin/                 # → darwinModules
│   ├── home/                   # → homeModules
│   └── flake/                  # → flakeModules
│
├── overlays/                   # → overlays
├── packages/                   # → packages
├── templates/                  # → templates (flake init -t)
│   └── python-uv/              # Example: Python + uv template
├── devshells/                  # → devShells
├── flake.lock
└── flake.nix
```

### Convention rules

| Path | Meaning |
|---|---|
| `hosts/nixos/<name>/default.nix` | NixOS system config for host `<name>` |
| `hosts/nixos/<name>.nix` | NixOS system config for host `<name>` (flat file) |
| `hosts/nixos/<name>/users/<user>.nix` | Home Manager config for `<user>` on host `<name>` |
| `hosts/darwin/<name>/default.nix` | Darwin system config for host `<name>` |
| `hosts/darwin/<name>/users/<user>.nix` | Home Manager config for `<user>` on Darwin host `<name>` |
| **`hosts/iso/<name>/default.nix`** | **NixOS ISO config for `<name>`** |
| **`hosts/iso/<name>/users/<user>.nix`** | **Home Manager config for `<user>` on the ISO** |
| `hosts/home/<user>.nix` | Standalone Home Manager config for `<user>` |
| `packages/<name>.nix` or `packages/<name>/default.nix` | Package definition |
| `devshells/<name>.nix` or `devshells/<name>/default.nix` | Dev shell definition |
| `modules/<type>/<name>.nix` or `modules/<type>/<name>/default.nix` | Module definition |
| `overlays/<name>.nix` or `overlays/<name>/default.nix` | Overlay definition |
| `templates/<name>/` | Flake template directory (any files inside) |
| `templates/<name>/template.nix` | *(Optional)* Template metadata `{ description = "..."; }` |

> If both `foo.nix` and `foo/default.nix` exist in the same directory, `foo/default.nix` takes precedence.
>
> Template directories are auto-discovered — any subdirectory under `templates/` becomes a template. No `.nix` file required inside. Optionally add `template.nix` for a custom description.

---

## ISO configurations

`hosts/iso/` is the dedicated directory for building NixOS ISO images (installer/live media). It works the same as `hosts/nixos/` but automatically imports the `installation-cd-minimal.nix` profile from nixpkgs, so your ISO gets a proper bootable installer environment.

### What you get automatically

Every ISO host gets the same wiring as a regular NixOS host:

- **Home Manager** — full integration with per-user home configs from `users/`
- **User discovery** — `users.users.<name>` auto-created with correct home directory
- **Common Nix settings** — `allowUnfree`, `experimental-features`, `max-jobs` (all `mkDefault`, overridable)
- **Special args** — `inputs` and `flake` (same as `self`) passed to all modules

On top of that, nix-wire imports the NixOS installer profile, giving you a bootable ISO.

### Example

```text
hosts/iso/
└── rescue/
    ├── users/
    │   └── nixos.nix        # Home config for the "nixos" user on the ISO
    └── default.nix          # ISO system config
```

```nix
# hosts/iso/rescue/default.nix
{ pkgs, inputs, ... }:
{
  imports = [ inputs.self.nixosModules.default ];

  nixpkgs.hostPlatform = "x86_64-linux";

  environment.systemPackages = with pkgs; [ git disko ];

  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
}
```

```nix
# hosts/iso/rescue/users/nixos.nix
{ flake, ... }:
{
  imports = [
    flake.homeModules.shell
    flake.homeModules.editor
  ];
}
```

### Building the ISO

The ISO is available as `isoConfigurations.<name>`:

```nix
# In your flake (e.g. via flake-parts):
{ self, ... }: {
  flake.iso = self.isoConfigurations.rescue.config.system.build.isoImage;
}
```

Then build with:

```bash
nix build .#iso.iso
```

### Custom installer profile

By default, nix-wire uses `installation-cd-minimal.nix`. To use a different profile (e.g. the graphical installer), pass `installerModule`:

```nix
# In your mkFlake call:
inputs.nix-wire.mkFlake {
  inherit inputs;
  iso = "hosts/iso";
  # Use the graphical installer profile instead
  # installerModule is currently a global setting in mkIsoConfigs
}
```

---

## Templates

`templates/` is the directory for [flake templates](https://nixos.wiki/wiki/Flakes#Flake_templates) — project scaffolds that users can initialize with `nix flake init -t`.

### How it works

Every subdirectory under `templates/` becomes a template. No `.nix` file required — any directory is accepted.

Optionally, add a `template.nix` inside the directory for a custom description:

```nix
# templates/python-uv/template.nix
{
  description = "Python project with uv and direnv";
}
```

Without `template.nix`, the template name is used as the description.

### Example

```text
templates/
└── python-uv/
    ├── .envrc
    ├── .gitignore
    ├── flake.nix
    └── template.nix      # Optional metadata
```

### Using templates

```bash
# List available templates
nix flake show github:your-org/your-flake

# Initialize from a template
mkdir my-project && cd my-project && git init
nix flake init -t github:your-org/your-flake#python-uv
```

---

## How it works

nix-wire is built on [flake-parts](https://flake.parts/) and provides a single entry point: `mkFlake`.

### `mkFlake` parameters

| Parameter | Default | Description |
|---|---|---|
| `inputs` | *(required)* | Your flake inputs |
| `prefix` | `inputs.self` | Base path for directory scanning |
| `systems` | `[x86_64-linux aarch64-linux x86_64-darwin aarch64-darwin]` | Supported systems |
| `packages` | `"packages"` | Directory name for packages |
| `devShells` | `"devshells"` | Directory name for dev shells |
| `hosts` | `"hosts"` | Directory name for host configs |
| `iso` | `"hosts/iso"` | Directory name for ISO configs (relative to prefix) |
| `templates` | `"templates"` | Directory name for flake templates |
| `home` | `true` | Enable home-manager integration for hosts |
| `imports` | `[]` | Additional flake-parts modules |

### Auto-wiring for hosts

For every host under `hosts/nixos/`, `hosts/darwin/`, and `hosts/iso/`, nix-wire automatically:

1. **Creates the system configuration** using `nixpkgs.lib.nixosSystem` or `nix-darwin.lib.darwinSystem`
2. **Discovers users** from the `users/` subdirectory and creates `users.users.<name>` entries
3. **Wires Home Manager** — imports the HM NixOS/Darwin module and sets up `home-manager.users.<name>` to import each user's config
4. **Sets `extraSpecialArgs`** — `{ inherit inputs; flake = inputs.self; }` available in all modules
5. **Applies common defaults** — `allowUnfree`, `experimental-features`, `max-jobs` (all via `mkDefault`)

### Special args

All host and home-manager modules receive:

- `inputs` — your flake inputs
- `flake` — alias for `inputs.self` (e.g. `flake.homeModules.shell`)

---

## Acknowledgements

We're aware of similar projects like [blueprint](https://github.com/numtide/blueprint) and many others in the Nix ecosystem. **nix-wire** intentionally keeps things bare minimum to focus solely on wiring flake configurations without additional complexity.

---

## TODOs

- [ ] Better template / test structure
- [ ] Add CI with checks (formatting, evaluation, etc.)
- [ ] Integrate `nix flake check` *(recommended, ensures configs evaluate properly; may require minimal test modules)*
- [ ] GitBook docs
