variable "gke_config" {
  description = "Cluster configuration"
  type        = map(any)
  default     = {}
}
