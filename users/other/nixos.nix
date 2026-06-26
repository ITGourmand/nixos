{ pkgs, ... }: {

  imports = [ ./preservation.nix ];
  
  users.users.other = {
    isNormalUser = true;
    group = "users";
    description = "Compte Invité";
    hashedPassword = "$6$CSAvZoqO4Egw5qRs$He9N2vJg68W2j0Ryy6dA1MLqSqWNY.xRNsoR5Wllr1xdJv4GOvmczvkW8KSzSyHhpty2EzDPoKr.FjKu8rf2M1";
    extraGroups = [ "networkmanager" ];
  };
}