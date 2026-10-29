variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts or os."

  validation {
    condition     = alltrue([for h in var.hosts : contains(["debian", "ubuntu", "rocky", "almalinux", "rhel", "centos", "fedora"], try(h.os, "debian"))])
    error_message = "A host object's os must be one of debian, ubuntu, rocky, almalinux, rhel, centos or fedora."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "certs" {
  type        = map(list(string))
  description = "Certificates to get, by name, each with the domains it covers, such as { example = [\"example.com\", \"www.example.com\"] }. Every host gets every certificate."

  validation {
    condition     = length(var.certs) > 0
    error_message = "certs needs at least one certificate."
  }

  validation {
    condition     = alltrue([for name in keys(var.certs) : can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*$", name))])
    error_message = "Certificate names may use letters, digits, ., - and _, and start with a letter or digit."
  }

  validation {
    condition     = alltrue([for d in flatten(values(var.certs)) : can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z0-9-]{2,63}$", d))]) && alltrue([for ds in values(var.certs) : length(ds) > 0])
    error_message = "Each certificate needs at least one domain, and each domain must be a full name such as \"www.example.com\". Wildcards need a DNS challenge, which this circuit doesn't do."
  }
}

variable "email" {
  type        = string
  default     = null
  description = "Email address for the ACME account. When null, the account is registered without one."

  validation {
    condition     = var.email == null || can(regex("^[^@\\s']+@[^@\\s']+\\.[^@\\s']+$", coalesce(var.email, "-")))
    error_message = "email must be an email address."
  }
}

variable "method" {
  type        = string
  default     = "standalone"
  description = "How certbot answers the HTTP challenge: \"standalone\" runs its own server on port 80, \"webroot\" writes files under webroot_path for a web server already on port 80, \"nginx\" uses the running nginx."

  validation {
    condition     = contains(["standalone", "webroot", "nginx"], var.method)
    error_message = "method must be \"standalone\", \"webroot\" or \"nginx\"."
  }
}

variable "webroot_path" {
  type        = string
  default     = "/var/www/html"
  description = "Directory your web server serves on port 80, for method = \"webroot\"."

  validation {
    condition     = startswith(var.webroot_path, "/") && can(regex("^[A-Za-z0-9/._-]+$", var.webroot_path))
    error_message = "webroot_path must be an absolute path of letters, digits, /, ., - and _."
  }
}

variable "staging" {
  type        = bool
  default     = false
  description = "Use Let's Encrypt's staging server, whose certificates browsers don't trust and whose rate limits are far higher."
}

variable "acme_server" {
  type        = string
  default     = null
  description = "ACME directory URL of another certificate authority. When null, Let's Encrypt."

  validation {
    condition     = var.acme_server == null || can(regex("^https://[^\\s']+$", coalesce(var.acme_server, "-")))
    error_message = "acme_server must be an https:// URL."
  }

  validation {
    condition     = var.acme_server == null || !var.staging
    error_message = "Set staging or acme_server, not both."
  }
}

variable "deploy_hook" {
  type        = string
  default     = null
  description = "Shell command to run after a certificate is issued or renewed, such as \"systemctl reload nginx\"."
}
