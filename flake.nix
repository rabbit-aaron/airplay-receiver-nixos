{
  description = "marshall — AirPlay 2 receiver on Raspberry Pi 3 (NixOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    stanmore2.url = "github:rabbit-aaron/marshall-stanmore-2-rust";
    volume-sync.url = "github:rabbit-aaron/shairplay-stanmore-2-volume-sync-rust";
  };

  outputs = { self, nixpkgs, stanmore2, volume-sync }: {
    nixosConfigurations.marshall = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./configuration.nix
        stanmore2.nixosModules.default
        volume-sync.nixosModules.default
      ];
    };
  };
}
