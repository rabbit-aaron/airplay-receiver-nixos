{ pkgs, ... }:
let
  version = "0.1.0";
  target = "aarch64-unknown-linux-musl";

  # Prebuilt static musl binary from GitHub Releases. Overriding the module's
  # `package` with this means the crane source build is never evaluated (option
  # defaults are lazy), so no Rust toolchain enters the build closure. The static
  # ELF runs as-is on NixOS (no interpreter/patchelf/runtime deps).
  volume-sync-bin = pkgs.stdenvNoCC.mkDerivation {
    pname = "volume-sync";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/rabbit-aaron/shairplay-stanmore-2-volume-sync-rust/releases/download/v${version}/volume-sync-v${version}-${target}.tar.gz";
      hash = "sha256-+R/Y0MRvQVludBmS7gDS94rhl+lm17J0LShq//Xu6fU=";
    };
    installPhase = ''
      runHook preInstall
      install -Dm755 volume-sync $out/bin/volume-sync
      runHook postInstall
    '';
    dontStrip = true;
    meta.mainProgram = "volume-sync";
  };
in
{
  # Drives the speaker's hardware volume from the AirPlay slider: subscribes to
  # the volume shairport-sync publishes (marshall/volume, dB) and republishes it
  # as an 0..32 command to the stanmore2 bridge. All three (shairport-sync,
  # volume-sync, stanmore2) must talk to the SAME broker (192.168.1.3:1883).
  services.volume-sync = {
    enable = true;
    package = volume-sync-bin;  # prebuilt binary, not the source build
    shairplayVolumeTopic = "marshall/volume";  # shairport topic="marshall" + publish_parsed
    environment = {
      MQTT_HOSTNAME = "192.168.1.3";
      MQTT_PORT = "1883";
      MQTT_USERNAME = "RabbitMQTT";
      STANMORE2_VOLUME_COMMAND_TOPIC = "stanmore2/command/set_volume";
      MAX_VOLUME = "24";  # cap the speaker's 0..32 scale at 24
    };
    # Only MQTT_PASSWORD is secret; kept out of the store via the env file.
    environmentFile = "/etc/nix-env/volume-sync.env";
  };
}
