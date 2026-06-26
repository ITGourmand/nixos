.
├── flake.nix                  # Entrée principale du Flake
├── disko.nix                  # Partitionnement du disque (Btrfs / Tmpfs)
├── hardware-configuration.nix # Configuration matérielle générée automatiquement
├── configuration.nix          # Point d'entrée NixOS (centralise les imports système)
│
├── system/                    # --- COIN SYSTÈME ---
│   ├── core.nix               # Paramètres de base Nix, caches, paramètres système essentiels
│   ├── boot.nix               # Chargeur de démarrage GRUB / Noyau
│   ├── network.nix            # Gestion réseau (HostName, NetworkManager)
│   ├── hardware.nix           # Pilotes graphiques (NVIDIA), microcode
│   ├── desktop.nix            # Environnement graphique (Plasma 6, SDDM), Audio (Pipewire), Localisation
│   ├── preservation.nix       # Gestion de l'impermanence (fichiers/dossiers persistants système & user)
│   └── maintenance.nix        # Automatisation des tâches (GC, optimisations store, backups systemd)
│
└── users/
    ├── default.nix            # L'INGÉNIEUR MULTI-UTILISATEURS (Fonctions Nix)
    ├── root.nix               # Compte root sécurisé
    ├── gourmand/
    │   ├── nixos.nix          # Customisation Système pour gourmand (ex: Groupes, Sudo)
    │   └── home.nix           # Apps & Dotfiles personnels de gourmand
    └── other/
        ├── nixos.nix          # Customisation Système pour other (ex: pas de Sudo)
        └── home.nix           # Apps & Dotfiles personnels de other