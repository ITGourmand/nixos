{ pkgs, ... }: {
  boot.tmp.useTmpfs = true;
  boot.tmp.cleanOnBoot = true;

  preservation = {
    enable = true;
    preserveAt."/persist" = {
      directories = [
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/nixos"
        "/var/lib/sddm"
        "/var/lib/AccountsService"
        { directory = "/etc/NetworkManager/system-connections"; mode = "0700"; }
        "/etc/nixos"
        { directory = "/root/.ssh"; mode = "0700"; }
      ];

      files = [
        { file = "/etc/machine-id"; inInitrd = true; }
        { file = "/etc/ssh/ssh_host_rsa_key"; how = "symlink"; configureParent = true; }
        { file = "/etc/ssh/ssh_host_ed25519_key"; how = "symlink"; configureParent = true; }
        { file = "/root/.gitconfig"; }
      ];
    };
  };

  systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

  environment.systemPackages = [
    (pkgs.writeScriptBin "fs-diff" ''
      #!/usr/bin/env bash
      CURRENT_USER=$(whoami)
      if [ "$CURRENT_USER" = "root" ]; then
        echo "Erreur : Lancez fs-diff depuis votre compte utilisateur normal."
        exit 1
      fi
      echo "=== Fichiers non-persistés découverts dans le Home de ($CURRENT_USER) ==="
      find "$HOME" -xdev -mindepth 1 -maxdepth 3 -not -path '*/.cache*' | while read -r path; do
        if [ -L "$path" ] || mountpoint -q "$path"; then continue; fi
        echo "$path"
      done
    '')
  ];
}
