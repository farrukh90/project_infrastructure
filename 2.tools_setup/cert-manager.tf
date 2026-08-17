module "cert-manager-ns" {
  source = "farrukh90/ns/kubernetes"
  name   = "cert-manager"

  annotations = {
    application = "cert-manager"
  }

  labels = {
    managedby = "terraform"
  }
}


# -------------------------------------------------------
# Install cert-manager
# -------------------------------------------------------

module "cert-mananger-terraform-helm" {
  source = "farrukh90/release/helm"

  deployment_name      = "cert-manager"
  deployment_namespace = module.cert-manager-ns.name
  chart                = "cert-manager"
  chart_version        = var.cert-manager-config["chart_version"]
  repository           = "https://charts.jetstack.io"

  values_yaml = <<EOF
global:
  leaderElection:
    namespace: cert-manager

crds:
  enabled: true
EOF
}


# -------------------------------------------------------
# GCP Service Account for cert-manager DNS-01
# -------------------------------------------------------

resource "google_service_account" "cert_manager_dns01" {
  account_id   = "cert-manager-dns01"
  display_name = "Used by cert-manager for DNS-01 challenges"
  project      = var.project_id
}


# Give cert-manager permission to manage Cloud DNS records
resource "google_project_iam_member" "cert_manager_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"

  member = "serviceAccount:${google_service_account.cert_manager_dns01.email}"
}


# Create GCP service account key
resource "google_service_account_key" "cert_manager_dns01" {
  service_account_id = google_service_account.cert_manager_dns01.name
}


# -------------------------------------------------------
# Store GCP credentials inside cert-manager namespace
# -------------------------------------------------------

resource "kubernetes_secret_v1" "cert_manager_dns01" {
  metadata {
    name      = "clouddns-dns01-solver"
    namespace = module.cert-manager-ns.name
  }

  data = {
    "key.json" = base64decode(
      google_service_account_key.cert_manager_dns01.private_key
    )
  }

  type = "Opaque"

  depends_on = [
    module.cert-mananger-terraform-helm
  ]
}


# -------------------------------------------------------
# Public Let's Encrypt ClusterIssuer
# Uses HTTP-01 through public nginx
# -------------------------------------------------------

resource "null_resource" "letsencrypt_prod" {
  depends_on = [
    module.cert-mananger-terraform-helm
  ]

  triggers = {
    email = var.email
  }

  provisioner "local-exec" {
    command = <<EOF
kubectl apply -f - <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${var.email}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
YAML
EOF
  }
}

# -------------------------------------------------------
# Internal Let's Encrypt ClusterIssuer
# Uses DNS-01 through Google Cloud DNS
# -------------------------------------------------------

resource "null_resource" "letsencrypt_internal" {
  depends_on = [
    module.cert-mananger-terraform-helm,
    kubernetes_secret_v1.cert_manager_dns01,
    google_project_iam_member.cert_manager_dns_admin
  ]

  triggers = {
    email      = var.email
    project_id = var.project_id
  }

  provisioner "local-exec" {
    command = <<EOF
kubectl apply -f - <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-internal
spec:
  acme:
    email: ${var.email}

    server: https://acme-v02.api.letsencrypt.org/directory

    privateKeySecretRef:
      name: letsencrypt-internal

    solvers:
      - dns01:
          cloudDNS:
            project: ${var.project_id}

            serviceAccountSecretRef:
              name: clouddns-dns01-solver
              key: key.json
YAML
EOF
  }
}