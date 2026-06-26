# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./wireless.nix
  ];

  swapDevices = [
    {
      device = "/swapfile";
      size = 4096;
    }
  ];

  zramSwap = {
    enable = true;
    algorithm = "lz4";
    memoryPercent = 100;
  };

  # I used this so Claude can debug easily
  # security.sudo.wheelNeedsPassword = false;

  networking.timeServers = ["192.168.1.1"];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.timeout = 1;

  boot.blacklistedKernelModules = [ "snd_bcm2835" ];
  hardware.deviceTree = {
    enable = true;
    overlays = [
      {
        name = "hifiberry-dac";
        dtsFile = ./hifiberry-dac.dts;
      }
    ];
  };


  networking.hostName = "marshall"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = false;

  # Set your time zone.
  time.timeZone = "Australia/Sydney";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;


  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound (ALSA).
  hardware.alsa.enablePersistence = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rabbit = {
     isNormalUser = true;
     extraGroups = [ "wheel" "audio" ];
     packages = with pkgs; [
       tree
     ];
  };

  # programs.firefox.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
     vim
     wget
     curl
     htop
     alsa-utils
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # AirPlay 2 receiver
  services.shairport-sync = {
    enable = true;
    package = pkgs.shairport-sync.override { enableAirplay2 = true; };
    arguments = "-a Marshall";
    openFirewall = true;
    settings = {
      general = {
        output_backend = "alsa";
        audio_backend_buffer_desired_length_in_seconds = 0.1;
        audio_backend_silent_lead_in_time = 0.0;
      };
      alsa = {
        output_device = "hw:0";
      };
    };
  };
  systemd.services.shairport-sync.serviceConfig = {
    StateDirectory = "shairport-sync";
    RestartSec = 3;
  };
  systemd.services.nqptp = {
    description = "NQPTP - PTP timing for AirPlay 2";
    wantedBy = [ "multi-user.target" ];
    before = [ "shairport-sync.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.nqptp}/bin/nqptp";
      Restart = "always";
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      3689  # DACP remote control
      5000  # AirPlay HTTP
      7000  # AirPlay 2 RTSP
    ];
    allowedUDPPorts = [
      319 320   # NQPTP (PTP timing)
      5353      # mDNS/Avahi
    ];
    allowedTCPPortRanges = [
      { from = 32768; to = 60999; }     # ephemeral ports for AirPlay 2
    ];
    allowedUDPPortRanges = [
      { from = 6000; to = 6009; }      # RTP audio streaming
      { from = 32768; to = 60999; }     # ephemeral ports for AirPlay 2
    ];
  };

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?

  networking.wireless.enable = true;
}
