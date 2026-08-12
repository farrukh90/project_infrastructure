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
