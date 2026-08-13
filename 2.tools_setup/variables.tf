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

variable "ingress-controller-config" {
  type        = map(any)
  description = "Please define ingress-controller configurations"
  default = {
    deployment_name          = "ingress-controller"
    chart_version            = "0.29.0"
    loadBalancerSourceRanges = "0.0.0.0/0"
  }
}

variable "vault" {
  description = "Enable / Disable vault service"
  type        = bool
  default     = false
}
