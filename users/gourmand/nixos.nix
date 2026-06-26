{ pkgs, ... }: {


  imports = [ ./preservation.nix ];

  
  users.users.gourmand = {
    isNormalUser = true;
    group = "users";
    description = "Anthony Gourmand";
    hashedPassword = "$6$ljMbl6WfazcC.I51$.xUH/4ERAb00rF0USlmYJe0UkvWnQpw/2HNUUbh5oTUcu2TkXntu.uuATBG8KEZiARSKiooLhpz6PLIXuq2Ib/";
    extraGroups = [ "networkmanager" "wheel" ];
  };
}