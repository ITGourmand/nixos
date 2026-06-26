{ ... }: {


  # boot.loader.grub.efiSupport = true;
  # boot.loader.grub.efiInstallAsRemovable = true;
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";

  #boot.loader.grub.devices = [ "/dev/sda" ];
  boot.loader.grub.enable = true;
  boot.loader.grub.useOSProber = true;
  boot.loader.timeout = 20;

}
