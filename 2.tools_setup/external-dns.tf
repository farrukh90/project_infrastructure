module "external-dns-ns" {
  source = "farrukh90/ns/kubernetes"
  name   = "external-dns"
  annotations = {
    application = "external-dns"
  }
  labels = {
    managedby = "terraform"
  }
}

# Creates GCP service account called "pro-external-dns"
resource "google_service_account" "external-dns" {
  account_id   = "pro-external-dns"
  display_name = "Used for external-dns"
  project      = var.project_id
}

# Creates a key for "pro-external-dns"  GCP service account
resource "google_service_account_key" "external-dns" {
  service_account_id = google_service_account.external-dns.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Attaches DNS Admin role to above service account
resource "google_project_iam_binding" "externald-dns" {
  project = var.project_id
  role    = "roles/dns.admin"
  members = [
    "serviceAccount:${google_service_account.external-dns.email}"
  ]
}

# Creates local kubernetes secret called external-dns in external-dns namespace
resource "kubernetes_secret" "external_dns_secret" {
  metadata {
    name      = "external-dns"
    namespace = module.external-dns-ns.name
  }
  data = {
    "credentials.json" = base64decode(google_service_account_key.external-dns.private_key)
  }
  type = "generic"
}

module "external-dns" {
  source     = "farrukh90/appdeploy/helm"
  name       = "external-dns"
  namespace  = "external-dns"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  wait       = false
  values = [<<-EOF

global:
  security:
    allowInsecureImages: true

image:
  registry: registry.k8s.io
  repository: external-dns/external-dns
  tag: v0.16.0

provider: google

google: 
  project: ${var.project_id}
  serviceAccountSecret: external-dns

rbac:
  create: true

  EOF
  ]
}
