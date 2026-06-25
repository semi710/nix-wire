# Building ISOs with nix-wire

How to create bootable NixOS ISO images (installer/live media) with
nix-wire's auto-wiring.

---

## Overview

nix-wire treats ISOs as a special category of NixOS host. They live in
`hosts/iso/` and are built as **per-system packages** (not as
`nixosConfigurations`). This means:

- `nix build .#rescue` produces a native-arch ISO for your current machine
- The ISO derivation is a regular package — works with `nix build`, CI, caches
- The full NixOS config is inspectable via `passthru.config`

## Directory structure

```text
hosts/iso/
└── rescue/
    ├── default.nix          # ISO system config
    └── users/
        └── nixos.nix        # Home config for the "nixos" user
```

ISO hosts follow the **same conventions** as regular NixOS hosts:

- Flat file (`rescue.nix`) or directory (`rescue/default.nix`)
- `users/` subdirectory for per-user Home Manager configs
- Special args (`inputs`, `flake`) available in all modules

## What you get automatically

Every ISO host gets the same wiring as a regular NixOS host, plus the
installer profile:

| Feature | Source |
|---|---|
| Home Manager | Auto-imported from `users/` |
| User discovery | `users.users.<name>` from `users/` |
| Common Nix settings | `allowUnfree`, `experimental-features`, `max-jobs` |
| Special args | `inputs`, `flake` |
| Installer profile | `installation-cd-minimal.nix` from nixpkgs |
| `networking.hostName` | Set to the ISO name |

## Example ISO config

```nix
# hosts/iso/rescue/default.nix
{ pkgs, inputs, ... }:
{
  imports = [ inputs.self.nixosModules.default ];

  # Do NOT set nixpkgs.hostPlatform here — nix-wire derives the platform
  # from the build system so `nix build .#iso` produces a native-arch ISO.

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

!!! warning "Don't set nixpkgs.hostPlatform"
    nix-wire derives the platform from the build system (`system` parameter
    in `perSystem`). Setting `nixpkgs.hostPlatform` manually in an ISO
    config would conflict with the arch-aware evaluation. Leave it out.

---

## Building the ISO

```bash
# Build a native-arch ISO (x86_64 on x86_64-linux, aarch64 on aarch64-linux)
nix build .#rescue

# Result: ./result/iso/nixos-*.iso
```

Nix auto-resolves the bare name to the current system's package, so you
don't need to specify the system.

### Explicit system

```bash
# Build for a specific architecture
nix build .#packages.x86_64-linux.rescue
nix build .#packages.aarch64-linux.rescue
```

!!! note "Linux only"
    ISOs are NixOS-specific. Darwin builds are automatically skipped
    (`lib.hasSuffix "-linux" system` check in `mkIsoPackages`).

---

## Inspecting the ISO config

The full NixOS evaluation is attached as `passthru.config`. You can inspect
any option without building:

```bash
# Check the hostname
nix eval .#packages.x86_64-linux.rescue \
  --apply 'x: x.passthru.config.networking.hostName'

# Check if SSH is enabled
nix eval .#packages.aarch64-linux.rescue \
  --apply 'x: x.passthru.config.services.openssh.enable'

# List system packages
nix eval .#packages.x86_64-linux.rescue \
  --apply 'x: builtins.map (p: p.name) x.passthru.config.environment.systemPackages'
```

---

## Custom installer profile

By default, nix-wire imports `installation-cd-minimal.nix` from nixpkgs'
`modulesPath`. To use a different profile:

Available profiles in `nixpkgs/modules/installer/cd-dvd/`:

| Profile | Description |
|---|---|
| `installation-cd-minimal.nix` | Minimal text-mode installer (default) |
| `installation-cd-minimal-new-kernel.nix` | Minimal with latest kernel |
| `installation-cd-graphical.nix` | Graphical (GUI) installer |
| `installation-cd-graphical-calamares.nix` | Calamares-based GUI installer |

!!! note "installerModule is per-ISO"
    The `installerModule` parameter is set in `mkIsoPackages` and applies
    to all ISOs in the `hosts/iso/` directory. To use different profiles
    per ISO, you'd need to customize the `mkFlake` call or handle it in the
    ISO's own config via `imports`.

---

## How it works internally

```nix
mkIsoPackages = { dir, home ? true, system, installerModule ? "installation-cd-minimal.nix" }:
  lib.optionalAttrs (lib.hasSuffix "-linux" system) (
    wireGeneric {
      inherit dir;
      buildFn = path: name:
        let
          eval = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = commonSpecialArgs;
            modules = isoModules home path dir name installerModule;
          };
          iso = eval.config.system.build.isoImage;
        in
        iso // {
          passthru = (iso.passthru or {}) // { config = eval.config; };
        };
    }
  );
```

The `isoModules` helper assembles the module list:

```nix
isoModules = home: path: dir: name: installerModule:
  commonModules("nixos", home, path, dir, name)
  ++ [ ({ modulesPath, ... }: {
       imports = [ "${modulesPath}/installer/cd-dvd/${installerModule}" ];
     })
     { networking.hostName = mkDefault name; }
  ];
```

This is DRY — it reuses `commonModules` (the same module list as regular
NixOS hosts) and adds the installer profile import on top.

---

## ISO with multiple users

```text
hosts/iso/
└── rescue/
    ├── default.nix
    └── users/
        ├── root.nix         # Home config for root
        └── nixos.nix        # Home config for nixos user
```

Both users are auto-discovered. `users.users.root` and
`users.users.nixos` are created, and Home Manager configs are wired for
both.

---

## Real-world use case: rescue disk

A common pattern is a rescue ISO with disk tools, SSH, and a familiar
shell:

```nix
# hosts/iso/rescue/default.nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git
    disko
    btrfs-progs
    cryptsetup
    smartmontools
    nvme-cli
  ];

  networking.networkmanager.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Auto-login as root on the console
  services.getty.autologinUser = "root";
}
```

```nix
# hosts/iso/rescue/users/root.nix
{ pkgs, ... }:
{
  home.stateVersion = "25.11";
  programs.zsh.enable = true;
  home.packages = with pkgs; [ neovim tmux ripgrep ];
}
```

```bash
nix build .#rescue
# Write to USB:
sudo dd if=./result/iso/*.iso of=/dev/sdX bs=4M status=progress
```
