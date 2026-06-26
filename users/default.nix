{ config, lib, pkgs, stateVersion, activeUsers, ... }: {
  
  imports = [
    ./root.nix
  ] ++ map (name: ./. + "/${name}/nixos.nix") activeUsers; 

  # =========================================================================
  # 1. Gestion Générique des Permissions Système (Root voit tout, isolation des users)
  # =========================================================================
  systemd.tmpfiles.rules = [
    "d /etc/nixos       0755 root root - -"
    "d /etc/nixos/users 0755 root root - -"
  ] ++ map (name: "d /etc/nixos/users/${name} 0700 ${name} users - -") activeUsers;

  # Script d'activation pour changer les propriétaires des fichiers récursivement
  system.activationScripts.fixNixosConfigOwnership = {
    text = lib.concatStringsSep "\n" (
      map (name: "chown -R ${name}:users /etc/nixos/users/${name}") activeUsers
    );
  };

  # =========================================================================
  # 2. Configuration Home Manager Générique
  # =========================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    
    extraSpecialArgs = { inherit stateVersion; };

    # Génère automatiquement le bloc de configuration pour chaque utilisateur actif
    users = lib.genAttrs activeUsers (name: { pkgs, config, ... }: {
      home.username = name;
      home.homeDirectory = "/home/${name}";
      home.stateVersion = stateVersion;

      # Création automatique du lien symbolique "hors du Store" dans le Home de l'user
      home.file."nixos-config".source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/users/${name}";

      imports = [ (./. + "/${name}/home.nix") ];
    });
  };
}