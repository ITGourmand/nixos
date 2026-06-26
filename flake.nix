{
  description = "Configuration NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    preservation.url = "github:nix-community/preservation";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = { nixpkgs, home-manager, ... }@inputs: 
    let 
      hostname = "PC-Gourmand";
    in {
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        
        specialArgs = { 
          inherit inputs hostname;
          stateVersion = "26.05";
          activeUsers = [ "gourmand" "other" ]; # Utilisateurs
        };

        modules = [
          inputs.disko.nixosModules.disko
          inputs.preservation.nixosModules.default
          home-manager.nixosModules.home-manager
          ./configuration.nix
        ];
      };
    };
}