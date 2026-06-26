{ pkgs, ... }:

let
  additionalDrives = [
    { 
      name = "SSD"; 
      id = "ata-TCSUNBOW_X3_240GB_2018092000529-part1"; 
      fsType = "ntfs3"; 
    }
    { 
      name = "Jeux"; 
      id = "ata-CT1000MX500SSD1_2045E4C6EACA-part2"; 
      fsType = "ntfs3"; 
    }
    { 
      name = "TO2"; 
      id = "ata-WDC_WD20EZBX-00AYRA0_WD-WXB2A613A29Z-part2"; 
      fsType = "ntfs3"; 
    }
    { 
      name = "TO"; 
      id = "ata-ST2000DM001-1ER164_Z4Z48980-part1"; 
      fsType = "ntfs3"; 
    }
    { 
      name = "ArchLinux"; # Added your external OS partition here
      id = "ata-SAMSUNG_HD320KJ_S0PAJDQP802182-part1"; 
      fsType = "ext4"; 
    }
  ];

  ntfsDrives = builtins.filter (d: d.fsType == "ntfs3") additionalDrives;
in
{
  # 1. Interface graphique & Session Manager
  services.xserver.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.desktopManager.plasma6.enable = true;

  # Nettoyage des bloatwares KDE par défaut
  services.xserver.excludePackages = [ pkgs.xterm ];
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    dolphin elisa kate okular discover qrca ark
  ];


  # 2. Localisation & Clavier
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "fr_FR.UTF-8";
  services.xserver.xkb.layout = "fr";
  console.useXkbConfig = true;

  # 3. Serveur Audio (PipeWire)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Xbox Controller Driver
  hardware.xone.enable = true;

  # --- Dynamic Filesystem Mounting ---

  # Active le montage automatique graphique
  services.udisks2.enable = true;
  security.polkit.enable = true;
  services.gvfs.enable = true;
  
  systemd.services.ntfsfix-before-mount = {
    description = "Nettoyer automatiquement le dirty bit des disques NTFS avant montage";
    wantedBy = [ "local-fs.target" ];
    
    # Dit à systemd de s'exécuter impérativement AVANT les points de montage de tes disques
    before = map (d: "mnt-${d.name}.mount") ntfsDrives;
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # Applique ntfsfix de manière sécurisée
    script = builtins.concatStringsSep "\n" (
      map (d: "${pkgs.ntfs3g}/bin/ntfsfix -d /dev/disk/by-id/${d.id} || true") ntfsDrives
    );
  };

  # --- CONFIGURATION DYNAMIQUE DES DISQUES ---
  
  # S'assure que les dossiers cibles (/mnt/Jeux, /mnt/TO, etc.) existent
  systemd.tmpfiles.rules = map (d: "d /mnt/${d.name} 0755 root root") additionalDrives;

  # Génère proprement la configuration des disques
  fileSystems = builtins.listToAttrs (map (d: {
    name = "/mnt/${d.name}";
    value = {
      device = "/dev/disk/by-id/${d.id}";
      fsType = d.fsType;
      options = [ "rw" "uid=1000" "nofail" "x-gvfs-show" ];
    };
  }) additionalDrives);
}