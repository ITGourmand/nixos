{ config, lib, pkgs, stateVersion, ... }: {
  
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    ./system/core.nix
    ./system/boot.nix
    ./system/network.nix
    ./system/hardware.nix
    ./system/desktop.nix
    ./system/preservation.nix
    ./system/maintenance.nix

    ./users
  ];

  # Version d'état globale du système
  system.stateVersion = stateVersion; 
}