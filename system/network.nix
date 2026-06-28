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
    
    # SSDP : autorise les réponses UDP des TVs Samsung (discovery UPnP)
    allowedUDPPorts = [ 1900 ];
    
    # Autorise le trafic multicast SSDP
    allowedUDPPortRanges = [
      { from = 1900; to = 1900; }
    ];


  # Autoriser le multicast SSDP (239.255.255.250)
  extraCommands = ''
    iptables -A INPUT -d 239.255.255.250 -p udp --dport 1900 -j ACCEPT
    ip6tables -A INPUT -d ff02::c -p udp --dport 1900 -j ACCEPT
  '';
  extraStopCommands = ''
    iptables -D INPUT -d 239.255.255.250 -p udp --dport 1900 -j ACCEPT 2>/dev/null || true
    ip6tables -D INPUT -d ff02::c -p udp --dport 1900 -j ACCEPT 2>/dev/null || true
  '';

    # Le serveur HTTP local (port dynamique ou fixe) pour le streaming
    # Décommente et ajuste si tu utilises un port fixe :
    # allowedTCPPorts = [ 8080 ];
  };
  
  # Par défaut, le pare-feu bloque tout le trafic entrant inutile.
  # Si vous avez besoin d'ouvrir des ports spécifiques (ex: SSH, Syncthing, etc.), décommentez et remplissez ici :
  # networking.firewall.allowedTCPPorts = [ 22 ]; # Exemple : ouvre le port 22 pour le SSH
  # networking.firewall.allowedUDPPorts = [ ];

}