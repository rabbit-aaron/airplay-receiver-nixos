# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

let
  # shairport-sync's config file lives in the world-readable /nix/store, so the
  # MQTT password is a @MQTT_PASSWORD@ placeholder there. At service start this
  # splices the real password (from the 0600 /etc/nix-env/shairport-sync.env)
  # into a copy in the runtime dir, readable only by the shairport user.
  shairportConfgen = pkgs.writeShellScript "shairport-mqtt-config" ''
    set -eu
    . /etc/nix-env/shairport-sync.env   # provides MQTT_PASSWORD
    out=/run/shairport-sync/shairport-sync.conf
    ${pkgs.gnused}/bin/sed "s|@MQTT_PASSWORD@|$MQTT_PASSWORD|" \
      /etc/shairport-sync.conf > "$out"
    ${pkgs.coreutils}/bin/chown shairport:shairport "$out"
    ${pkgs.coreutils}/bin/chmod 600 "$out"
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ./wireless.nix
    ./stanmore2.nix
    ./volume-sync.nix
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

  security.sudo.wheelNeedsPassword = false;

  # Allow pushing remotely-built (unsigned) closures from deploy.sh.
  nix.settings.trusted-users = [ "root" "rabbit" ];

  networking.timeServers = ["192.168.1.1"];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.generic-extlinux-compatible.configurationLimit = 5;
  boot.loader.timeout = 1;

  # Garbage-collect old store paths so pushed generations don't accumulate.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

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

  # Bluetooth — onboard Pi 3 radio (BCM43438 on the PL011 UART / ttyAMA0).
  # The mainline bcm2837-rpi-3-b DTB has the bluetooth serdev node, so the btbcm
  # driver binds automatically; it just needs the vendor firmware blob present.
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];  # provides BCM43430A1.hcd
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true;  # extra BLE D-Bus interfaces (advertising, etc.)
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
    openFirewall = true;
    settings = {
      general = {
        name = "Marshall";
        output_backend = "alsa";
        audio_backend_buffer_desired_length_in_seconds = 0.1;
        audio_backend_silent_lead_in_time = 0.0;
        # Don't attenuate the audio (stays at 100%); volume-sync drives the
        # speaker's hardware volume from the AirPlay slider over MQTT instead.
        ignore_volume_control = "yes";
      };
      alsa = {
        output_device = "hw:0";
      };
      # Publish the AirPlay volume (volume-sync consumes marshall/volume) and
      # accept remote control over MQTT. password is a placeholder spliced in at
      # runtime so the real secret stays out of the store (see shairportConfgen).
      mqtt = {
        enabled = "yes";
        hostname = "192.168.1.3";
        port = 1883;
        username = "RabbitMQTT";
        password = "@MQTT_PASSWORD@";
        topic = "marshall";
        publish_parsed = "yes";
        enable_remote = "yes";
        publish_cover = "yes";
        enable_autodiscovery = "yes";
      };
    };
  };
  systemd.services.shairport-sync.serviceConfig = {
    StateDirectory = "shairport-sync";
    Restart = lib.mkForce "always";
    RestartSec = 3;
    # "+" runs as root so it can read the 0600 secret; the daemon then runs from
    # the spliced runtime config instead of the placeholder one in the store.
    ExecStartPre = "+${shairportConfgen}";
    ExecStart = lib.mkForce
      "${lib.getExe config.services.shairport-sync.package} -c /run/shairport-sync/shairport-sync.conf";
  };

  # Watchdog: shairport-sync can wedge — process alive but no longer connectable,
  # so systemd's Restart= never fires. The reliable "AirPlay is available" signal
  # is a resolved _raop._tcp mDNS record for this host; if it disappears, restart.
  systemd.services.shairport-watchdog = {
    description = "Restart shairport-sync if its AirPlay mDNS advertisement disappears";
    after = [ "shairport-sync.service" "avahi-daemon.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.avahi pkgs.systemd ];
    script = ''
      check() {
        avahi-browse -ptr _raop._tcp 2>/dev/null \
          | grep '^=;' | grep -q ';${config.networking.hostName}.local;'
      }
      # Two probes so a single flaky mDNS lookup doesn't trigger a needless
      # restart (which would cut any active stream).
      if check; then exit 0; fi
      sleep 5
      if check; then exit 0; fi
      echo "shairport-sync AirPlay advertisement missing — restarting"
      systemctl restart shairport-sync.service
    '';
  };
  systemd.timers.shairport-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
    };
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
