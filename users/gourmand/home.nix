{ pkgs, ... }: {

  imports = [ ./alias.nix ];

  
  home.packages = with pkgs; [
    google-chrome
    vscode
    geany
    python3
    qpwgraph
    fastfetch
    nemo
    nemo-fileroller
    file-roller
    nixd
    nixfmt-rfc-style
    vlc
  ];

  xdg.desktopEntries = {
    "org.kde.kwalletmanager" = { name = "KWalletManager"; noDisplay = true; };
    "cups" = { name = "Interface Web de CUPS"; noDisplay = true; };
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "nemo.desktop" ];
      
      "application/zip" = [ "org.gnome.FileRoller.desktop" ];
      "application/x-tar" = [ "org.gnome.FileRoller.desktop" ];
      "application/x-7z-compressed" = [ "org.gnome.FileRoller.desktop" ];
      "application/x-rar" = [ "org.gnome.FileRoller.desktop" ];

      # --- GEANY PAR DÉFAUT ---
      "text/plain" = [ "geany.desktop" ];
      "application/json" = [ "geany.desktop" ];
      "text/markdown" = [ "geany.desktop" ];
      "text/javascript" = [ "geany.desktop" ];
      "application/xml" = [ "geany.desktop" ];
    };
  };

  programs.bash = {
    enable = true;
    initExtra = "fastfetch";
  };

  programs.home-manager.enable = true;
}