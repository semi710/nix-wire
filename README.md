# nix-wire

**A lightweight Nix flake auto-wiring library.**

Drop your configs into the right directories - nix-wire builds the flake
outputs for you. No manual imports, no boilerplate, no per-host wiring.

Built on [flake-parts](https://flake.parts/). Used by [ndots](https://github.com/semi710/ndots).

---

![GitHub stars](https://img.shields.io/github/stars/semi710/nix-wire) ![GitHub forks](https://img.shields.io/github/forks/semi710/nix-wire) ![GitHub last commit](https://img.shields.io/github/last-commit/semi710/nix-wire) ![License: MIT](https://img.shields.io/badge/license-MIT-green)

<h3>📚 <a href="https://nix-wire.semi.sh">nix-wire.semi.sh</a> - Full Documentation</h3>
<sub>API Reference · Architecture · Guides · Convention Rules · ISO · Templates</sub>

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

That's it. Everything else is discovered from the directory tree.

---

## Related

- **[ndots](https://github.com/semi710/ndots)** - NixOS + nix-darwin config built with nix-wire
- **[utils](https://github.com/semi710/utils)** - Utility scripts flake
- **[blueprint](https://github.com/numtide/blueprint)** - Similar project (nix-wire is intentionally more minimal)
