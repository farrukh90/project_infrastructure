resource "google_dns_managed_zone" "project" {
  name        = "project"
  dns_name    = "${var.dns_name}."
  description = "Used for project"
  labels = {
    managed_by = "terraform"
  }
}
