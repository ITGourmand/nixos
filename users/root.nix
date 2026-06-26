{ pkgs, lib,... }:
let
  mesScripts = with pkgs; [
    (writeScriptBin "nix-switch" ''
      #!/usr/bin/env bash
      set -e
      DIR="/etc/nixos"
      REMOTE="https://github.com/ITGourmand/nixos"
      if ! sudo git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
        echo "Init dépôt git dans $DIR..."
        sudo git -C "$DIR" init
        sudo git -C "$DIR" remote add origin "$REMOTE"
        echo "Remote GitHub configuré."
      fi
      sudo git -C "$DIR" add .
      sudo nixos-rebuild switch --flake "$DIR"
      sudo systemctl start nix-clean-by-count.service
    '')

    (writeScriptBin "nix-pull" ''
      #!/usr/bin/env bash
      set -e
      echo "Stash des changements locaux..."
      sudo git -C /etc/nixos stash
      echo "Pull depuis GitHub..."
      sudo git -C /etc/nixos pull --rebase origin main
      sudo git -C /etc/nixos stash pop 2>/dev/null || true
      sudo nixos-rebuild switch --flake /etc/nixos
      sudo systemctl start nix-clean-by-count.service
    '')
  ];
in
{

  environment.systemPackages = with pkgs; [
    git
    tree
  ] ++ mesScripts;

  environment.shellAliases = lib.mkForce {
    # nix-switch = "sudo git -C /etc/nixos add . && sudo nixos-rebuild switch --flake /etc/nixos && sudo systemctl start nix-clean-by-count.service";
    nix-list  = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";
    nix-clean = "sudo nix-collect-garbage --delete-older-than 3d && sudo nix-store --optimise";
  };

  users.users.root.hashedPassword = "$6$ljMbl6WfazcC.I51$.xUH/4ERAb00rF0USlmYJe0UkvWnQpw/2HNUUbh5oTUcu2TkXntu.uuATBG8KEZiARSKiooLhpz6PLIXuq2Ib/";
}
