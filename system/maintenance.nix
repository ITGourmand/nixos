{ config, pkgs, ... }: {


  # =========================================================================
  # Optimisation et Nettoyage Automatique du Système
  # =========================================================================
  
  nix.gc.automatic = false;
  nix.settings.auto-optimise-store = true;

  systemd.timers.nix-clean-by-count = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "nix-clean-by-count.service";
    };
  };

  systemd.services.nix-clean-by-count = {
    description = "Nettoyage strict NixOS: Garde uniquement les 3 dernières générations";
    path = with pkgs; [ coreutils nix util-linux os-prober ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      # 1. Supprime le surplus du profil système (garde les 3 derniers)
      ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --delete-generations +3
      
      # 2. Libère l'espace disque
      ${pkgs.nix}/bin/nix-store --gc
      
      # 3. Réinitialisation du compteur
      cd /nix/var/nix/profiles/
      if ls -d system-*-link >/dev/null 2>&1; then
        mkdir -p tmp_rename
        count=1
        for link in $(ls -vd system-*-link); do
          mv "$link" "tmp_rename/system-$count-link"
          count=$((count + 1))
        done
        mv tmp_rename/system-*-link .
        rmdir tmp_rename
        
        last_gen=$((count - 1))
        ln -nsf "system-$last_gen-link" system
      fi
      
      # 4. Met à jour le menu GRUB pour refléter les nouveaux numéros 1, 2, 3
      /run/current-system/bin/switch-to-configuration boot
    '';
  };


  # =========================================================================
  # Trigger de Sauvegarde Intelligente (Lundi et Jeudi à 18h00)
  # =========================================================================
  systemd.timers.backup-nixos-config = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon,Thu *-*-* 18:00:00";
      Persistent = true;
      Unit = "backup-nixos-config.service";
    };
  };

  systemd.services.backup-nixos-config = {
    description = "Sauvegarde de la configuration Flake de NixOS";
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      mkdir -p /persist/backups/nixos
      cp -r /etc/nixos/. /persist/backups/nixos/
      echo "Sauvegarde NixOS effectuée avec succès dans le stockage persistant."
    '';
  };
}