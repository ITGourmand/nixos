{
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;

  disko.devices.nodev = {
    "/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=25%"
        "mode=755"
      ];
    };
  };

  disko.devices.disk.main = {
    device = "/dev/disk/by-id/ata-V_Series_SATA_SSD_120GB_214610695503455";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {

        # 0. Partition BIOS (1 Mo)
        biosboot = {
          size = "1M";
          type = "EF02";
          priority = 1;
        };

        # 1. Partition de Boot (1 Go)
        boot = {
          size = "1G";
          priority = 2;
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/boot";
          };
        };

        # 2. Partition SWAP (8 Go)
        swap = {
          size = "8G";
          priority = 3;
          content = {
            type = "swap";
          };
        };

        # 3. Partition Stockage Btrfs (Le reste du SSD)
        root = {
          size = "100%";
          priority = 4;
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "nix" = {
                mountpoint = "/nix";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "persist" = {
                mountpoint = "/persist";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
            };
          };
        };
      };
    };
  };
}
