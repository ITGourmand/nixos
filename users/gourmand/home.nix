{ pkgs, ... }:

let
  pkgs-fixed = pkgs.extend (final: prev: {
    file-roller = prev.file-roller.overrideAttrs (oldAttrs: {
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
      postFixup = (oldAttrs.postFixup or "") + ''
        wrapProgram $out/bin/file-roller --set GDK_BACKEND x11
      '';
    });
  });
in {

  imports = [ ./alias.nix ];

  
  home.packages = with pkgs-fixed; [
    google-chrome
    vscode
    geany
    python3
    qpwgraph
    fastfetch
    nemo-with-extensions
    file-roller
    p7zip
    nixd
    nixfmt
    vlc
    discord
    prismlauncher
    steam
    umu-launcher
    heroic
    antigravity-ide
    android-studio
    jetbrains.idea
    
    icoutils
  ];  
  
  xdg.dataFile."thumbnailers/exe.thumbnailer".text = ''
    [Thumbnailer Entry]
    TryExec=${pkgs.icoutils}/bin/wrestool
    Exec=exe-thumbnailer %i %o
    MimeType=application/vnd.microsoft.portable-executable;application/x-ms-dos-executable;application/x-msdownload;
  '';

  xdg.desktopEntries = {
    "org.kde.kwalletmanager" = { name = "KWalletManager"; noDisplay = true; };
    "cups" = { name = "Interface Web de CUPS"; noDisplay = true; };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
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

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "ITGourmand";
        email = "contactpro.gourmand@gmail.com";
      };
    };
  };

  programs.home-manager.enable = true;
}
