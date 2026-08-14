variable "dns_name" {
  description = "Please specify your domain"
  type        = string
  default     = "example.com"
}

variable "project_id" {
  description = "Please specify your project ID"
  type        = string
  default     = ""
}

variable "gke_config" {
  description = "Cluster configuration"
  type        = map(any)
  default     = {}
}

variable "ingress" {
  description = "Enable / Disable ingress service"
  type        = bool
  default     = false
}

variable "vault-config" {
  type        = map(any)
  description = "Please define vault configurations"
  default = {
    deployment_name = "vault"
    chart_version   = "0.29.0"
  }
}

variable "vault" {
  description = "Enable / Disable vault service"
  type        = bool
  default     = false
}


variable "ingress-controller-config" {
  type        = map(any)
  description = "Please define ingress-controller configurations"
  default = {
    deployment_name          = "ingress-controller"
    chart_version            = "0.29.0"
    loadBalancerSourceRanges = "0.0.0.0/0"
  }
}

variable "grafana-config" {
  type        = map(any)
  description = "Please define grafana configurations"
  default = {
    deployment_name = "grafana"
    chart_version   = "0.29.0"
  }
}

variable "grafana" {
  description = "Enable / Disable grafana service"
  type        = bool
  default     = false
}

variable "prometheus-config" {
  type        = map(any)
  description = "Please define prometheus configurations"
  default = {
    deployment_name = "prometheus"
    chart_version   = "29.23.1"
  }
}

variable "prometheus" {
  description = "Enable / Disable prometheus service"
  type        = bool
  default     = false
}

# This block is used to setup cert-manager
variable "cert-manager-config" {
  type        = map(any)
  description = "Please define cert-manager configurations"
  default = {
    deployment_name = "cert-manager"
    chart_version   = "1.16.3"
  }
}

# This block is used to setup lets-encrypt backup
variable "lets-encrypt-config" {
  type        = map(any)
  description = "Please define lets-encrypt configurations"
  default = {
    deployment_name = "lets-encrypt"
    chart_version   = "0.1.0"
  }
}

variable "lets-encrypt" {
  description = "Deploy lets-encrypt or no?"
  type        = bool
  default     = false
}
