# Facts give each host's distribution. Rocky Linux, AlmaLinux and RHEL get
# certbot from EPEL, and the Red Hat family names its renewal timer
# differently from Debian and Ubuntu.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = try(each.value.os, self.os_id) == self.os_id
      error_message = "Host ${each.key} is ${self.os_id}, not the ${try(each.value.os, "")} its os says."
    }
  }
}

locals {
  # A host object's os stands in for the facts of a host created in the
  # same plan, which can't be read until it exists.
  os     = { for name, h in var.hosts : name => try(h.os, data.conn3x_host.facts[name].os_id) }
  family = { for name, o in local.os : name => contains(["debian", "ubuntu"], o) ? "debian" : "redhat" }

  # Rocky Linux and AlmaLinux ship epel-release in their own extras
  # repository. RHEL doesn't, so EPEL has to be on there already.
  epel_hosts = { for name, h in var.hosts : name => h if contains(["rocky", "almalinux"], local.os[name]) }

  # Debian's package turns its timer on. Fedora's and EPEL's ship theirs
  # off, under another name.
  timer = { for name, f in local.family : name => f == "debian" ? "certbot.timer" : "certbot-renew.timer" }

  server = coalesce(var.acme_server, var.staging ? "https://acme-staging-v02.api.letsencrypt.org/directory" : "https://acme-v02.api.letsencrypt.org/directory")

  domains = { for name, ds in var.certs : name => sort(distinct([for d in ds : lower(d)])) }

  hook_file = "/etc/letsencrypt/renewal-hooks/deploy/conn3x"

  method_args = {
    standalone = "--standalone"
    webroot    = "--webroot -w ${var.webroot_path}"
    nginx      = "--nginx"
  }[var.method]

  account_args = var.email == null ? "--register-unsafely-without-email" : "--email '${var.email}'"

  # certbot runs hooks in renewal-hooks/deploy only when it renews, so the
  # first issue runs the hook itself, with the variables certbot would set.
  issue = { for name, ds in local.domains : name => join(" ", compact([
    "certbot certonly --non-interactive --agree-tos --quiet",
    local.account_args,
    "--server '${local.server}'",
    "--cert-name ${name}",
    # The command only runs when the certificate on the host doesn't match,
    # so a certificate that isn't due yet still has to be replaced.
    "--force-renewal",
    local.method_args,
    "-d ${join(",", ds)}",
    var.deploy_hook == null ? "" : "&& RENEWED_LINEAGE=/etc/letsencrypt/live/${name} RENEWED_DOMAINS='${join(" ", ds)}' ${local.hook_file}",
  ])) }

  # Holds when the certificate exists, covers exactly these domains, and
  # renews from the same server with the same method. Changing any of
  # them gets a new certificate.
  issued = { for name, ds in local.domains : name => join(" && ", [
    "f=/etc/letsencrypt/live/${name}/cert.pem",
    "r=/etc/letsencrypt/renewal/${name}.conf",
    "test -f \"$f\"",
    "grep -qxF 'server = ${local.server}' \"$r\"",
    "grep -qxF 'authenticator = ${var.method}' \"$r\"",
    "[ \"$(openssl x509 -in \"$f\" -noout -ext subjectAltName | tr , '\\n' | sed -n 's/^ *DNS://p' | LC_ALL=C sort | tr '\\n' ' ')\" = '${join(" ", ds)} ' ]",
  ]) }
}

circuit "epel" {
  hosts = local.epel_hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "release" {
    package {
      name = "epel-release"
    }
  }
}

circuit "certbot" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "package" {
    depends_on = [conn3x_package.epel__release]
    package {
      name = "certbot"
    }
  }

  # Reads the domains on an existing certificate.
  step "openssl" {
    package {
      name = "openssl"
    }
  }

  step "nginx_plugin" {
    for_each = var.method == "nginx" ? { nginx = true } : {}
    package {
      name = "python3-certbot-nginx"
    }
  }

  step "deploy_hook" {
    for_each = var.deploy_hook == null ? {} : { hook = var.deploy_hook }
    file {
      path      = local.hook_file
      mode      = "0755"
      content   = "#!/bin/sh\n# Written by Conn3x. Changes here are overwritten on the next apply.\n${item.value}\n"
      on_remove = "delete"
    }
  }

  step "cert" {
    for_each = local.issue
    command {
      command = item.value
      unless  = local.issued[item.key]
    }
  }

  step "renewal" {
    service {
      name    = local.timer[each.key]
      state   = "started"
      enabled = true
    }
  }
}
