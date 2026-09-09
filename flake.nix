{
  description = "Falk's reproducible server and development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      mkHome =
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit system; };
          modules = [ ./home/aemon.nix ];
        };
    in
    {
      homeConfigurations = {
        "aemon@x86_64-linux" = mkHome "x86_64-linux";
        "aemon@aarch64-linux" = mkHome "aarch64-linux";
      };

      checks = forAllSystems (system: {
        "aemon-home" = self.homeConfigurations."aemon@${system}".activationPackage;
      });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
