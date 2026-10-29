#!/usr/bin/env sh
# Starts a throwaway host on 127.0.0.1:$PORT (default 2222) that Conn3x can
# configure, with a fresh SSH key and its host key in ./known_hosts.
# CONTAINERFILE picks another image, such as one of Conn3x's test images.
#
# A container can't get a real certificate, so this also starts Pebble,
# Let's Encrypt's test ACME server, and a DNS server that sends every name
# to the host. Pebble's own HTTPS certificate is trusted on the host, and
# nowhere else.
#
# Needs Podman, since the host runs systemd. CI uses rootful Podman:
# CONTAINER_CONNECTION=podman-machine-default-root on a Mac, or
# PODMAN="sudo podman" on Linux.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2222}
containerfile=${CONTAINERFILE:-Containerfile}
name=${NAME:-circuit-certbot}
pebble=ghcr.io/letsencrypt/pebble:2.10.1
dns=ghcr.io/letsencrypt/pebble-challtestsrv:2.10.1

podman=${PODMAN:-podman}
[ -f id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C "$name" -f id_ed25519
$podman build -q -f "$containerfile" -t "$name" "$(dirname "$containerfile")" >/dev/null
$podman rm -f -v "$name" "$name-pebble" "$name-dns" >/dev/null 2>&1 || true
$podman network rm "$name" >/dev/null 2>&1 || true
$podman network create "$name" >/dev/null

$podman run -d --name "$name" --network "$name" --systemd=always \
  -p "127.0.0.1:$port:22" "$name" >/dev/null
ip=$($podman inspect -f "{{(index .NetworkSettings.Networks \"$name\").IPAddress}}" "$name")

# Answers every A query with the host's address, so Pebble checks the
# challenge on the host whatever the domain.
$podman run -d --name "$name-dns" --network "$name" --network-alias dns "$dns" \
  -defaultIPv4 "$ip" -defaultIPv6 "" -http01 "" -https01 "" -tlsalpn01 "" -doh "" -management "" >/dev/null

# Pebble's own config, but checking HTTP challenges on port 80 like Let's
# Encrypt does, instead of 5002.
$podman create --name "$name-pebble" --network "$name" --network-alias pebble \
  -e PEBBLE_VA_NOSLEEP=1 "$pebble" -config /test/config/pebble-config.json -dnsserver dns:8053 >/dev/null
$podman cp "$name-pebble:/test/config/pebble-config.json" - | tar -xO | sed 's/"httpPort": 5002/"httpPort": 80/' > pebble-config.json
$podman cp pebble-config.json "$name-pebble:/test/config/pebble-config.json"
$podman start "$name-pebble" >/dev/null

$podman exec -i "$name" sh -c 'cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys' < id_ed25519.pub
$podman exec "$name" timeout 60 systemctl is-system-running --wait >/dev/null 2>&1 || true

# certbot reaches Pebble at https://pebble:14000/dir, whose certificate is
# signed by Pebble's test CA.
$podman cp "$name-pebble:/test/certs/pebble.minica.pem" - | tar -xO |
  $podman exec -i "$name" sh -c '
    if [ -d /etc/pki/ca-trust/source/anchors ]; then
      cat > /etc/pki/ca-trust/source/anchors/pebble.pem && update-ca-trust
    else
      cat > /usr/local/share/ca-certificates/pebble.crt && update-ca-certificates >/dev/null 2>&1
    fi'

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ssh-keyscan -p "$port" 127.0.0.1 > known_hosts 2>/dev/null && [ -s known_hosts ]; then
    echo "Ready on 127.0.0.1:$port. Now run: conn3x init && conn3x apply -var port=$port"
    exit 0
  fi
  sleep 1
done
echo "The container started, but SSH didn't answer on 127.0.0.1:$port." >&2
exit 1
