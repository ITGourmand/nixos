{ pkgs, ... }: {

  programs.bash.shellAliases = {
    ll = "ls -la --color=auto";
    gcm = "git commit -m";
    scode = "sudo code --user-data-dir --no-sandbox";
  };

  home.packages = [
    (pkgs.writeScriptBin "nix-show" ''
      #!/usr/bin/env bash
      find . -type f -name "*.nix" | while read -r file; do
          echo "$file:"
          cat "$file"
          echo
      done
    '')
  ];
}