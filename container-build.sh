#!/bin/sh
# Runs inside the nixos/nix container (see docker-compose.yml). Builds the
# flake natively for aarch64, exports the closure to ./.artifact, then pushes
# and activates it on the Pi. Driven by env vars: PI_HOST, FLAKE_ATTR,
# BUILD_ONLY, PUSH_ONLY.
set -eu
export NIX_CONFIG="experimental-features = nix-command flakes"

# SSH keys need sane perms; the bind mount is read-only so copy them in.
mkdir -p /root/.ssh
cp -rL /ssh-in/. /root/.ssh/ 2>/dev/null || true
chmod 700 /root/.ssh || true
chmod 600 /root/.ssh/* 2>/dev/null || true

if [ "$PUSH_ONLY" != "1" ]; then
  # Build from a non-git copy so the flake picks up the gitignored
  # hardware-configuration.nix and wireless.nix (flakes ignore untracked files
  # inside a git tree).
  rm -rf /build
  cp -a /work /build
  cd /build
  rm -rf .git result

  # RELOCK re-pins inputs to their latest revs; otherwise just add missing ones
  # (keeps already-locked inputs pinned).
  if [ -n "${RELOCK:-}" ] && [ "$RELOCK" != "0" ]; then
    if [ "$RELOCK" = "1" ]; then
      echo ">> relocking flake.lock (updating all inputs)"
      nix flake update
    else
      echo ">> relocking flake.lock (updating inputs: $RELOCK)"
      nix flake update $RELOCK
    fi
  else
    echo ">> updating flake.lock (adds missing inputs only)"
    nix flake lock
  fi
  cp flake.lock /work/flake.lock   # persist back to the repo on the host

  echo ">> building .#$FLAKE_ATTR (aarch64-linux, native)"
  nix build ".#nixosConfigurations.$FLAKE_ATTR.config.system.build.toplevel"
  OUT="$(readlink -f result)"
  echo ">> built: $OUT"

  echo ">> exporting closure to ./.artifact"
  rm -rf /work/.artifact
  nix copy --to "file:///work/.artifact" "$OUT"
  printf '%s' "$OUT" > /work/.artifact-path

  if [ "$BUILD_ONLY" = "1" ]; then
    echo ">> BUILD_ONLY set — artifact saved, skipping push/activate"
    exit 0
  fi
fi

# Push phase: ship the saved artifact to the Pi (no rebuild) and activate it.
if [ ! -f /work/.artifact-path ] || [ ! -d /work/.artifact ]; then
  echo "!! no ./.artifact found — run a build first (BUILD_ONLY=1 ./deploy.sh)" >&2
  exit 1
fi
OUT="$(cat /work/.artifact-path)"
export OUT

# nix copy + remote activation need an ssh client, which the base image lacks.
nix shell nixpkgs#openssh -c sh -ec '
  export NIX_SSHOPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts"
  echo ">> copying $OUT to $PI_HOST (from ./.artifact)"
  nix copy --no-check-sigs --from "file:///work/.artifact" --to "ssh://$PI_HOST" "$OUT"
  echo ">> activating on $PI_HOST"
  ssh $NIX_SSHOPTS "$PI_HOST" \
    "sudo nix-env -p /nix/var/nix/profiles/system --set $OUT && sudo $OUT/bin/switch-to-configuration switch"
'
echo ">> done"
