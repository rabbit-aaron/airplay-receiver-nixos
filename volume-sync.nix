{
  # Drives the speaker's hardware volume from the AirPlay slider: subscribes to
  # the volume shairport-sync publishes (marshall/volume, dB) and republishes it
  # as an 0..32 command to the stanmore2 bridge. All three (shairport-sync,
  # volume-sync, stanmore2) must talk to the SAME broker (192.168.1.3:1883).
  services.volume-sync = {
    enable = true;
    shairplayVolumeTopic = "marshall/volume";  # shairport topic="marshall" + publish_parsed
    environment = {
      MQTT_HOSTNAME = "192.168.1.3";
      MQTT_PORT = "1883";
      MQTT_USERNAME = "RabbitMQTT";
      STANMORE2_VOLUME_COMMAND_TOPIC = "stanmore2/command/set_volume";
    };
    # Only MQTT_PASSWORD is secret; kept out of the store via the env file.
    environmentFile = "/etc/nix-env/volume-sync.env";
  };
}
