{ pkgs, ... }: {

  imports = [ ./alias.nix ];

  home.packages = with pkgs; [
    firefox
    vlc
    libreoffice
  ];

  programs.bash = {
    enable = true;
    initExtra = "echo 'Bienvenue sur ta session Invité!'";
  };

  programs.home-manager.enable = true;
}