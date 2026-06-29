{ lib, pkgs, ... }:
let
  version = "0.1.0";
  target = "aarch64-unknown-linux-gnu";

  # Prebuilt binary from GitHub Releases. Overriding the module's `package` with
  # this means the crane source build is never evaluated (option defaults are
  # lazy), so no Rust toolchain enters the build closure. Unlike volume-sync's
  # static musl binary, this is a glibc dynamic build, so autoPatchelfHook fixes
  # the ELF interpreter and links libdbus (btleplug's BlueZ backend) at runtime.
  stanmore2-bin = pkgs.stdenv.mkDerivation {
    pname = "stanmore2";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/rabbit-aaron/marshall-stanmore-2-rust/releases/download/v${version}/stanmore2-v${version}-${target}.tar.gz";
      hash = "sha256-8sQelhrYOCY1P3nPUE51cQE0qFbp0Ug1mxSasYbdemw=";
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.dbus pkgs.stdenv.cc.cc.lib ];  # libdbus-1, libgcc_s
    installPhase = ''
      runHook preInstall
      install -Dm755 stanmore2 $out/bin/stanmore2
      runHook postInstall
    '';
    meta.mainProgram = "stanmore2";
  };
in
{
  services.stanmore2 = {
    enable = true;
    package = stanmore2-bin;  # prebuilt binary, not the source build
    # Required by the module, but overridden at runtime: the real BLE_ADDRESS
    # (and all other config) comes from /etc/nix-env/stanmore2.env below.
    bleAddress = "via-environmentFile";
    environmentFile = "/etc/nix-env/stanmore2.env";
  };

  # Drop the module's BLE_ADDRESS=<bleAddress> Environment= line so the env file
  # is the only source of runtime config (keeps the MAC out of the nix store too).
  systemd.services.stanmore2.environment = lib.mkForce { };

  # The RPi 3's onboard BT chip occasionally loses the UART firmware-upload
  # handshake at boot, leaving hci0 down with a 00:00:00:00:00:00 address (so
  # the bridge dies with "no bluetooth adapter found"). Re-probing the driver
  # reliably reloads the firmware. If the adapter looks dead, rebind it before
  # the bridge starts. "+" runs it as root, which the sysfs writes require.
  systemd.services.stanmore2.serviceConfig.ExecStartPre =
    let
      btFixup = pkgs.writeShellScript "stanmore2-bt-fixup" ''
        addr=$(${pkgs.bluez}/bin/hciconfig hci0 2>/dev/null \
          | ${pkgs.gnugrep}/bin/grep -o 'BD Address: [0-9A-F:]*' || true)
        if [ -z "$addr" ] || echo "$addr" | ${pkgs.gnugrep}/bin/grep -q '00:00:00:00:00:00'; then
          echo ">> hci0 looks dead ($addr) — rebinding hci_uart_bcm"
          echo serial0-0 > /sys/bus/serial/drivers/hci_uart_bcm/unbind || true
          sleep 2
          echo serial0-0 > /sys/bus/serial/drivers/hci_uart_bcm/bind || true
          sleep 3
        fi
      '';
    in
    "+${btFixup}";
}
