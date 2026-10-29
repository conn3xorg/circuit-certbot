#!/usr/bin/env sh
# Removes the containers, their network and everything up.sh and Conn3x
# created here.
set -eu
cd "$(dirname "$0")"
podman=${PODMAN:-podman}
name=${NAME:-circuit-certbot}
$podman rm -f -v "$name" "$name-pebble" "$name-dns" >/dev/null 2>&1 || true
$podman network rm "$name" >/dev/null 2>&1 || true
rm -rf id_ed25519 id_ed25519.pub known_hosts pebble-config.json .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
echo "Removed."
