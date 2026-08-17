module "vpn-ns" {
  source = "farrukh90/ns/kubernetes"
  count  = var.vpn ? 1 : 0

  name = "vpn"

  annotations = {
    application = "wireguard"
  }

  labels = {
    managedby = "terraform"
  }
}


# Generate WireGuard admin password
resource "random_password" "wireguard_admin_password" {
  count = var.vpn ? 1 : 0

  length  = 24
  special = false
}


# Create Google Secret Manager secret container
resource "google_secret_manager_secret" "wireguard_private_key" {
  count     = var.vpn ? 1 : 0
  secret_id = "wireguard-private-key"

  replication {
    auto {}
  }
}


resource "google_secret_manager_secret" "wireguard_admin_password" {
  count     = var.vpn ? 1 : 0
  secret_id = "wireguard-admin-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "wireguard_admin_password" {
  count       = var.vpn ? 1 : 0
  secret      = google_secret_manager_secret.wireguard_admin_password[0].id
  secret_data = random_password.wireguard_admin_password[0].result
}


data "google_secret_manager_secret_version" "wireguard_admin_password" {
  count = var.vpn ? 1 : 0

  project = var.project_id
  secret  = google_secret_manager_secret.wireguard_admin_password[0].secret_id

  depends_on = [
    google_secret_manager_secret_version.wireguard_admin_password
  ]
}

# Install wg if needed and generate/store private key
# ONLY if Secret Manager does not already contain one
resource "null_resource" "wireguard_setup" {
  count = var.vpn ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      SECRET_NAME="wireguard-private-key"
      PROJECT_ID="${var.project_id}"

      if ! command -v wg >/dev/null 2>&1; then
        echo "wg not found. Installing wireguard-tools..."

        sudo apt-get update
        sudo apt-get install -y wireguard-tools
      else
        echo "wg is already installed."
      fi

      if gcloud secrets versions access latest \
        --secret="$SECRET_NAME" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then

        echo "WireGuard private key already exists in Secret Manager."

      else

        echo "Generating WireGuard private key..."

        wg genkey | \
        gcloud secrets versions add "$SECRET_NAME" \
          --project="$PROJECT_ID" \
          --data-file=-

        echo "WireGuard private key stored in Secret Manager."
      fi
    EOT
  }

  depends_on = [
    google_secret_manager_secret.wireguard_private_key
  ]
}



# Read private key from Google Secret Manager

data "google_secret_manager_secret_version" "wireguard_private_key" {
  count = var.vpn ? 1 : 0

  project = var.project_id
  secret  = google_secret_manager_secret.wireguard_private_key[0].secret_id

  depends_on = [
    null_resource.wireguard_setup
  ]
}


module "wireguard-terraform-helm" {
  source = "farrukh90/appdeploy/helm"
  count  = var.vpn ? 1 : 0

  name       = "wireguard"
  namespace  = module.vpn-ns[0].name
  chart      = "wg-access-server"
  repository = "https://place1.github.io/wg-access-server"

  values = [<<EOF

web:
  config:
    adminUsername: admin
    adminPassword: "${trimspace(data.google_secret_manager_secret_version.wireguard_admin_password[0].secret_data)}"

wireguard:
  config:
    privateKey: "${trimspace(data.google_secret_manager_secret_version.wireguard_private_key[0].secret_data)}"

  service:
    type: LoadBalancer

persistence:
  enabled: true
  size: 1Gi

ingress:
  enabled: true

  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod

  hosts:
    - vpn.${var.dns_name}

  tls:
    - secretName: wireguard-web-tls
      hosts:
        - vpn.${var.dns_name}

EOF
  ]

    depends_on = [
    null_resource.wireguard_setup,
    google_secret_manager_secret_version.wireguard_admin_password,
    module.vpn-ns
    ]

}
