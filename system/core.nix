{ pkgs, ... }: {
  # Autoriser les paquets propriétaires (NVIDIA, Chrome, VS Code)
  nixpkgs.config.allowUnfree = true;

  # Activer les Flakes de façon permanente
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- Pont pour exécutables génériques ---
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Bibliothèques de base essentielles
    stdenv.cc.cc
    zlib
    glib
    util-linux

    # Réseau et Sécurité
    openssl
    curl
    icu

    # Audio
    alsa-lib
    pulseaudio
    pipewire

    # Graphismes (X11, OpenGL et polices de caractères)
    libGL
    libva
    fontconfig
    freetype
    libx11
    libxcursor
    libxrandr
    libxext
    libxinerama
    libxi
    libxtst
    libxrender
    libxcomposite
    libxdamage
    libxfixes
    libxcb
    
    # Nécessaire pour beaucoup d'applications Electron (Discord, VS Code, etc.)
    nspr
    nss
    atk
    cairo
    pango
    gdk-pixbuf
    gtk3
    libdbusmenu-gtk3

  ];
}