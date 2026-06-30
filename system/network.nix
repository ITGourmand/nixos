{ hostname, ... }: {

  networking.hostName = hostname;
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "none";

  # 1. Configuration des DNS de Google (IPv4)
  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];
  
  # Optionnel : Force NetworkManager à injecter ces DNS en priorité
  networking.networkmanager.insertNameservers = [ "8.8.8.8" "8.8.4.4" ];

  # 2. Activation et configuration du Firewall
  networking.firewall = {
    enable = true;

    trustedInterfaces = [ "enp2s0" ]; 
  };
  
  # Par défaut, le pare-feu bloque tout le trafic entrant inutile.
  # Si vous avez besoin d'ouvrir des ports spécifiques (ex: SSH, Syncthing, etc.), décommentez et remplissez ici :
  # networking.firewall.allowedTCPPorts = [ 22 ]; # Exemple : ouvre le port 22 pour le SSH
  # networking.firewall.allowedUDPPorts = [ ];

}