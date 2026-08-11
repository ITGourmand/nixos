{ pkgs, ... }:
let
  username = "gourmand";

  jsonFile = ./preservation/persisted.json;

  persisted = if builtins.pathExists jsonFile
              then builtins.fromJSON (builtins.readFile jsonFile)
              else {};

  customDirs = persisted.directories.custom or [
    "Documents" "Images" "Bureau" "Projets" "Jeux" ".local/share"
  ];
  secureDirs = persisted.directories.secure or [
    ".ssh" ".local/share/keyrings"
  ];

  customFiles = persisted.files.custom or [
    ".gitconfig" ".nvidia-settings-rc"
  ];
  secureFiles = persisted.files.secure or [];

  mkDir = mode: dir: {
    directory = "/home/${username}/${dir}";
    user = username;
    group = "users";
    inherit mode;
  };

  mkFile = mode: file: {
    file = "/home/${username}/${file}";
    user = username;
    group = "users";
    inherit mode;
  };
in
{
  preservation.preserveAt."/persist" = {
    directories = (map (mkDir "0755") customDirs)
               ++ (map (mkDir "0700") secureDirs);

    files = (map (mkFile "0644") customFiles)
         ++ (map (mkFile "0600") secureFiles);
  };
}