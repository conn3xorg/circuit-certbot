# Local example

Applies circuit-certbot to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

A container can't get a certificate from Let's Encrypt, which has to reach it from the internet. So `up.sh` also starts [Pebble](https://github.com/letsencrypt/pebble), Let's Encrypt's small test server, and a DNS server that sends every name to the host container. The three share a Podman network of their own. Pebble's HTTPS certificate is added to the host container's trust store, so certbot accepts it there and nowhere else.

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To look at the result:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 certbot certificates
```

To try a renewal, pass Pebble's address. Without `--server`, `certbot renew --dry-run` goes to Let's Encrypt's staging server, whatever the certificate's renewal file says:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 \
  certbot renew --dry-run --no-random-sleep-on-renew --server https://pebble:14000/dir
```

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the containers, their network, the key and the state.
