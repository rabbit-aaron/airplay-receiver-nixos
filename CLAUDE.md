# CLAUDE.md

NixOS config for a Raspberry Pi 3 ("marshall") acting as an AirPlay 2 receiver
(shairport-sync + HiFiBerry/PCM5102A DAC) and a Marshall Stanmore II BLE↔MQTT
bridge. Built remotely on an Apple Silicon Mac (no local Nix) via Docker and
pushed to the Pi.

Two Rust sidecar services come in as flake inputs, each with its own NixOS
module + `nix-env/*.env` secret file:
- **stanmore2** (`marshall-stanmore-2-rust`) — BLE↔MQTT bridge to the speaker.
- **volume-sync** (`shairplay-stanmore-2-volume-sync-rust`) — pure-MQTT bridge
  that maps the AirPlay volume shairport-sync publishes (`marshall/volume`, dB)
  to the speaker's `0..32` scale and republishes it to stanmore2's
  `set_volume` topic. All three talk to the same broker (`192.168.1.3:1883`).
  shairport-sync runs `ignore_volume_control = "yes"` so this drives the
  speaker's hardware volume directly.

## Deploy workflow

The Mac has no Nix. `deploy.sh` runs the build inside an `nixos/nix` arm64
container (native aarch64, no QEMU) and pushes the closure to the Pi over SSH.
**The user runs all builds/deploys themselves** — do not run `deploy.sh`,
`docker compose`, or any build/push yourself unless explicitly asked. You may
edit files and run read-only SSH diagnostics on the Pi.

```bash
./deploy.sh                  # build, export ./.artifact, push, activate
BUILD_ONLY=1 ./deploy.sh     # build + export only (no Pi needed)
PUSH_ONLY=1  ./deploy.sh     # ship the already-built ./.artifact, no rebuild
RELOCK=1 ./deploy.sh         # re-pin all flake inputs before building
RELOCK=stanmore2 ./deploy.sh # re-pin only the named input(s)
PI_HOST=rabbit@1.2.3.4 ./deploy.sh
```

Pieces:
- `deploy.sh` — host entrypoint; fetches Pi-only files if missing, then runs compose.
- `docker-compose.yml` — the builder container + persistent `nix-store` / eval-cache volumes (only the first build is cold).
- `container-build.sh` — runs inside the container: relock/lock, build `toplevel`, export to `./.artifact`, `nix copy` to Pi, then `nix-env --set` + `switch-to-configuration switch`.

Pi: `rabbit@192.168.1.37`, hostname `marshall`, aarch64-linux. `rabbit` is a
trusted Nix user (so unsigned closures push) and has passwordless sudo.

## Gotchas

- **Flakes ignore untracked/gitignored files inside a git tree.** The build
  copies the repo to a non-git `/build` so it can see gitignored
  `hardware-configuration.nix` and `wireless.nix`. Keep that copy step.
- **`nix flake lock` only adds missing inputs**; it won't re-pin. Use `RELOCK=`
  to bump an already-locked input (e.g. the stanmore2 bridge).
- Module options often have a default-priority definition already; overriding
  needs `lib.mkForce` (e.g. shairport-sync's `Restart`).

## Secrets

Nothing secret goes in git or the world-readable `/nix/store`. Runtime secrets
live in `nix-env/*.env` (gitignored via `*.env`), staged locally and copied to
`/etc/nix-env/*.env` on the Pi.

- `nix-env/wireless.env` — `PSK_RABBIT=<hex psk>`. `wireless.nix` (gitignored)
  references it with `pskRaw = "ext:PSK_RABBIT"` + `networking.wireless.secretsFile`.
  `secretsFile` reads values literally (no quoting/escaping).
- `nix-env/stanmore2.env` — `BLE_ADDRESS`, `MQTT_*`. `stanmore2.nix` points the
  module's `environmentFile` at it and `lib.mkForce {}`s the module's
  `environment` so the env file is the only source of runtime config (keeps the
  BLE MAC out of the store too).
- `nix-env/volume-sync.env` — `MQTT_PASSWORD` only (topic/host/user aren't
  secret, so they live in `volume-sync.nix`).
- `nix-env/shairport-sync.env` — `MQTT_PASSWORD` only. shairport-sync's config
  is rendered to the world-readable store, so its `mqtt.password` is a
  `@MQTT_PASSWORD@` placeholder; a root `ExecStartPre` (`shairportConfgen` in
  `configuration.nix`) splices the real value into a 0600 runtime copy and the
  daemon runs from that via `-c`.

The `nix-env/*.env` files are not copied by `deploy.sh`; stage them to
`/etc/nix-env/` on the Pi manually (e.g. `scp nix-env/volume-sync.env
rabbit@192.168.1.37:/tmp/ && ssh ... sudo mv`).

## Pi 3 hardware quirks

- **Onboard Bluetooth (BCM43438 on the PL011 UART)** has no firmware in ROM; the
  kernel uploads `BCM43430A1.hcd` over the UART at every boot. The handshake
  occasionally times out (`command 0x0c14 tx timeout` / `Reading local name
  failed (-110)`) because the core clock that derives the UART baud rate scales
  dynamically — leaving `hci0` DOWN with a `00:00:00:00:00:00` address and
  stanmore2 failing with "no bluetooth adapter found". Fix is automated by an
  `ExecStartPre` in `stanmore2.nix` that rebinds `hci_uart_bcm` if the adapter
  looks dead. Manual recovery: unbind/bind `serial0-0` under
  `/sys/bus/serial/drivers/hci_uart_bcm/`.
- **shairport-sync can wedge** (process alive but unconnectable), which
  `Restart=on-failure` never catches. The `shairport-watchdog` timer in
  `configuration.nix` restarts it if the resolved `_raop._tcp` mDNS record for
  `marshall.local` disappears.

## Store hygiene

Every push creates a new system generation; Nix never auto-GCs. `configuration.nix`
sets `boot.loader.generic-extlinux-compatible.configurationLimit = 5` (boot menu
only) and `nix.gc` (weekly, 30-day). To reclaim space now:
`ssh rabbit@192.168.1.37 "sudo nix-collect-garbage -d"`.

## Key files

| File | Tracked | Purpose |
|------|---------|---------|
| `flake.nix` / `flake.lock` | no | wraps `configuration.nix`, pins nixpkgs + `stanmore2` + `volume-sync` inputs |
| `configuration.nix` | yes | main system config |
| `stanmore2.nix` | no | BLE bridge service config (secrets via env file, BT fixup) |
| `volume-sync.nix` | no | AirPlay→speaker volume bridge config (MQTT only) |
| `wireless.nix` | gitignored | WiFi (from `wireless.nix.example`) |
| `hardware-configuration.nix` | gitignored | generated per-machine; fetched from Pi by `deploy.sh` |
| `hifiberry-dac.dts` | yes | PCM5102A DAC device-tree overlay |
| `config.txt` | yes | Pi firmware config |
| `nix-env/*.env` | gitignored | runtime secrets → `/etc/nix-env/` on the Pi |
| `deploy.sh` / `docker-compose.yml` / `container-build.sh` | no | dockerized remote build+deploy |
