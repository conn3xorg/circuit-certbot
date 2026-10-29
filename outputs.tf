output "certificates" {
  description = "Paths of each certificate's files on every host, by certificate name: fullchain, privkey, cert and chain."
  value = { for name in keys(var.certs) : name => {
    fullchain = "/etc/letsencrypt/live/${name}/fullchain.pem"
    privkey   = "/etc/letsencrypt/live/${name}/privkey.pem"
    cert      = "/etc/letsencrypt/live/${name}/cert.pem"
    chain     = "/etc/letsencrypt/live/${name}/chain.pem"
  } }
}

output "acme_server" {
  description = "ACME directory URL the certificates come from."
  value       = local.server
}
