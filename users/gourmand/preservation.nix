{ pkgs, ... }:
let
  username = "gourmand";
  customDirs = [
    "Téléchargements" "Documents" "Images" "Bureau" "Projets"
    ".config" ".local/share" ".local/state"
    ".vscode" ".vscode-shared" ".copilot"
  ];
  secureDirs = [
    ".ssh" ".local/share/keyrings"
  ];
in
{
  preservation.preserveAt."/persist" = {
    directories = [
      #{ directory = "/home/${username}"; user = username; group = "users"; mode = "0700"; }
    ] 
    ++ (map (dir: { directory = "/home/${username}/${dir}"; user = username; group = "users"; mode = "0755"; }) customDirs)
    ++ (map (dir: { directory = "/home/${username}/${dir}"; user = username; group = "users"; mode = "0700"; }) secureDirs);

    files = map (file: { file = "/home/${username}/${file}"; user = username; group = "users"; mode = "0644"; }) [
      ".gitconfig" ".nvidia-settings-rc"
    ];
  };
}