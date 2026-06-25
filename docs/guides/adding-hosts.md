# Adding Hosts

How host auto-discovery works in nix-wire.

---

## Directory layout

Hosts live under `hosts/` (configurable via the `hosts` parameter):

```text
hosts/
├── nixos/          # → nixosConfigurations
├── darwin/         # → darwinConfigurations
├── iso/            # → packages.<system>.<name> (ISO images)
└── home/           # → legacyPackages.homeConfigurations (standalone HM)
```

## Two file styles

Each host can be defined as either a flat `.nix` file or a directory with
`default.nix`:

```text
hosts/nixos/
├── laptop.nix              # Flat file → nixosConfigurations.laptop
└── workstation/
    └── default.nix          # Directory → nixosConfigurations.workstation
```

!!! note "Precedence"
    If both `foo.nix` and `foo/default.nix` exist, the directory
    (`foo/default.nix`) wins. The flat file is silently dropped.

## When to use which

- **Flat file** - simple configs with no per-user home configs
- **Directory** - when you need a `users/` subdirectory for Home Manager

## Per-user Home Manager

Place user configs in a `users/` subdirectory inside any host directory:

```text
hosts/nixos/workstation/
├── default.nix              # System config for "workstation"
└── users/
    ├── alice.nix            # Home config for "alice"
    └── bob/
        └── default.nix      # Home config for "bob" (directory style)
```

nix-wire automatically:

1. **Creates user entries** - `users.users.alice` and `users.users.bob`
   with default `home` paths (`/home/alice`, `/home/bob`)
2. **Wires Home Manager** - imports `home-manager.nixosModules.home-manager`
3. **Sets up per-user configs** - `home-manager.users.alice` imports
   `alice.nix`, `home-manager.users.bob` imports `bob/default.nix`
4. **Passes special args** - `inputs` and `flake` available in user configs

### User config example

```nix
# hosts/nixos/workstation/users/alice.nix
{ flake, pkgs, ... }:
{
  home.stateVersion = "25.11";

  imports = [
    flake.homeModules.shell
  ];

  programs.git = {
    enable = true;
    userName = "Alice";
    userEmail = "alice@example.com";
  };

  home.packages = with pkgs; [ ripgrep fd bat ];
}
```

---

## What every host gets automatically

Regardless of the host type (NixOS, Darwin, ISO), every host gets:

| Feature | Default | Overridable? |
|---|---|---|
| `networking.hostName` | Set to the hostname | Yes (`mkDefault`) |
| `nixpkgs.config.allowUnfree` | `true` | Yes (`mkDefault`) |
| `nix.settings.experimental-features` | `["nix-command" "flakes"]` | Yes (`mkDefault`) |
| `nix.settings.max-jobs` | `"auto"` | Yes (`mkDefault`) |
| `nixpkgs.overlays` | All overlays from `inputs.self.overlays` | Yes |
| Home Manager integration | Enabled (if `home = true`) | Via `home` parameter |
| User discovery | From `users/` subdirectory | Automatic |
| Special args | `inputs`, `flake` | Automatic |

---

## Darwin-specific extras

Darwin hosts additionally get `sharedModules` with session path entries:

```nix
home.sessionPath = [
  "/etc/profiles/per-user/$USER/bin"     # home-manager binaries
  "/nix/var/nix/profiles/system/sw/bin"  # nix-darwin binaries
  "/usr/local/bin"                        # macOS GUI programs
];
```

This ensures home-manager and nix-darwin binaries are on the PATH for
zsh/bash sessions on macOS.

---

## Disabling Home Manager

If you don't want Home Manager integration for hosts:

```nix
outputs = inputs: inputs.nix-wire.mkFlake {
  inherit inputs;
  home = false;
};
```

This skips importing the home-manager module entirely. The `users/`
subdirectory is still scanned for user entries, but no Home Manager configs
are wired.

---

## Custom host directory name

```nix
outputs = inputs: inputs.nix-wire.mkFlake {
  inherit inputs;
  hosts = "machines";  # Use machines/ instead of hosts/
};
```

Now nix-wire looks for `machines/nixos/`, `machines/darwin/`, etc.

---

## Building hosts

```bash
# NixOS
sudo nixos-rebuild switch --flake .#laptop
sudo nixos-rebuild switch --flake .#workstation

# Darwin
darwin-rebuild switch --flake .#macbook
darwin-rebuild switch --flake .#office-mac

# Standalone Home Manager
home-manager switch --flake .#alice
```
