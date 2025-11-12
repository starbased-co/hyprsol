{
  description = "hyprsol - Complete monitor control (color temperature + hardware brightness) for Hyprland";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    {
      # Home Manager module
      homeManagerModules.default = import ./module.nix;
      homeManagerModules.hyprsol = import ./module.nix;

      # NixOS module (same implementation)
      nixosModules.default = import ./module.nix;
      nixosModules.hyprsol = import ./module.nix;
    };
}
