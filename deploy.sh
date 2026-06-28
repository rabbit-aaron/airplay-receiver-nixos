#!/usr/bin/env bash
# Host entrypoint. Fetches the Pi-only machine files if needed, then runs the
# dockerized build/push (see docker-compose.yml + container-build.sh).
# The /nix store is a persistent Docker volume, so only the first build is cold.
#
#   ./deploy.sh                # build, export ./.artifact, push, activate
#   BUILD_ONLY=1 ./deploy.sh   # build + export ./.artifact only (no Pi needed)
#   PUSH_ONLY=1  ./deploy.sh   # send the already-built ./.artifact, no rebuild
#   RELOCK=1 ./deploy.sh       # re-pin all flake inputs before building
#   RELOCK=stanmore2 ./deploy.sh   # re-pin only the named input(s)
#   PI_HOST=rabbit@1.2.3.4 ./deploy.sh
set -euo pipefail

export PI_HOST="${PI_HOST:-rabbit@192.168.1.37}"
export FLAKE_ATTR="${FLAKE_ATTR:-marshall}"
export BUILD_ONLY="${BUILD_ONLY:-0}"
export PUSH_ONLY="${PUSH_ONLY:-0}"
export RELOCK="${RELOCK:-}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

# Machine-specific files live only on the Pi (gitignored). Needed for the build,
# so pull them if missing — but not when we're only pushing a prebuilt artifact.
if [[ "$PUSH_ONLY" != "1" ]]; then
  for f in hardware-configuration.nix wireless.nix; do
    if [[ ! -f "$f" ]]; then
      echo ">> $f missing locally — fetching from $PI_HOST:/etc/nixos/$f"
      scp "$PI_HOST:/etc/nixos/$f" "./$f"
    fi
  done
fi

docker compose run --rm builder
