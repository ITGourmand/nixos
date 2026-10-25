{ pkgs, ... }: {

  programs.bash.shellAliases = {
    ll = "ls -lah --color=auto";
    gcm = "git commit -m";
  };

  home.packages = [
    # 1. nix-show
    (pkgs.writeShellScriptBin "nix-show" (builtins.readFile ./scripts/nix-show.sh))

    # 2. scode
    (pkgs.writeShellScriptBin "scode" (builtins.readFile ./scripts/scode.sh))

    # 3. setup-env
    (pkgs.writeShellScriptBin "setup-env" (builtins.readFile ./scripts/setup-env.sh))

    # 4. sumu-run
    (pkgs.writeShellApplication {
        name = "sumu-run";
        runtimeInputs = [ pkgs.bubblewrap pkgs.coreutils pkgs.umu-launcher pkgs.xdg-dbus-proxy pkgs.procps ];
        excludeShellChecks = [ "SC2329" ];
        text = builtins.readFile ./scripts/sumu-run.sh;
      })

    # 5. fs-diff-gui
    (pkgs.writers.writePython3Bin "fs_diff_gui" {
      libraries = [ pkgs.python3Packages.pyside6 ];
    } ''
      ${builtins.readFile ./scripts/fs_diff_constants.py}
      ${builtins.readFile ./scripts/fs_diff_gui.py}
    '')


  ];


}
