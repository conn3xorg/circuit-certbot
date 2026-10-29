variable "port" {
  type    = number
  default = 2222
}

module "certbot" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  # Pebble, started by up.sh. Leave acme_server out for Let's Encrypt.
  acme_server = "https://pebble:14000/dir"
  email       = "admin@example.com"

  certs = {
    box = ["box.example.test", "www.box.example.test"]
  }

  # Records which domains the last issue or renewal was for.
  deploy_hook = "echo \"$RENEWED_DOMAINS\" > /root/last-deploy"
}
