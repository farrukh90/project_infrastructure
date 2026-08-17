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


# Store admin password in Google Secret Manager
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

resource "kubernetes_service_v1" "wireguard_udp" {
  count = var.vpn ? 1 : 0

  metadata {
    name      = "wireguard-udp"
    namespace = module.vpn-ns[0].name
    annotations = {
      "external-dns.alpha.kubernetes.io/hostname" = "wg.${var.dns_name}"
    }
  }

  spec {
    selector = {
      "app.kubernetes.io/instance" = "wireguard"
      "app.kubernetes.io/name"     = "wg-easy"
    }

    port {
      name        = "wireguard"
      port        = 51820
      target_port = 51820
      protocol    = "UDP"
    }

    type = "LoadBalancer"
  }

  depends_on = [
    module.wireguard-terraform-helm
  ]
}

module "wireguard-terraform-helm" {
  source = "farrukh90/appdeploy/helm"
  count  = var.vpn ? 1 : 0

  name       = "wireguard"
  namespace  = module.vpn-ns[0].name
  chart      = "wg-easy"
  repository = "https://raw.githubusercontent.com/hansehe/wg-easy-helm/master/helm/charts"

  values = [<<EOF

environmentVariables:
  INSECURE: "true"
  DISABLE_IPV6: "true"
  INIT_ENABLED: "true"
  INIT_USERNAME: "admin"
  INIT_PASSWORD: "${trimspace(data.google_secret_manager_secret_version.wireguard_admin_password[0].secret_data)}"
  INIT_HOST: "wg.${var.dns_name}"
  INIT_PORT: "51820"

securityContext:
  privileged: true
  allowPrivilegeEscalation: true
  capabilities:
    add:
      - NET_ADMIN
      - SYS_MODULE

service:
  type: ClusterIP
  port: 51821

ingress:
  enabled: true
  className: nginx

  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

  hosts:
    - host: vpn.${var.dns_name}
      paths:
        - path: /
          pathType: Prefix

  tls:
    - secretName: wireguard-web-tls
      hosts:
        - vpn.${var.dns_name}

volume:
  enabled: true
  size: 1Gi

EOF
  ]

  depends_on = [
    google_secret_manager_secret_version.wireguard_admin_password
  ]
}


module "internal-ingress-ns" {
  source = "farrukh90/ns/kubernetes"
  count  = var.vpn ? 1 : 0
  name   = "internal-ingress"
  annotations = {
    application = "internal-ingress"
  }
  labels = {
    managedby = "terraform"
  }
}


module "internal-ingress-terraform-helm" {
  source     = "farrukh90/appdeploy/helm"
  count      = var.vpn ? 1 : 0
  name       = "internal-ingress"
  namespace  = module.internal-ingress-ns[0].name
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"

  values = [<<EOF
controller:

  allowSnippetAnnotations: true

  replicaCount: 2

  minReadySeconds: 5

  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1

  podDisruptionBudget:
    enabled: true
    minAvailable: 1

  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-nginx
          app.kubernetes.io/component: controller

  ingressClassResource:
    name: internal
    enabled: true
    default: false
    controllerValue: k8s.io/internal-ingress-nginx

  ingressClass: internal

  electionID: internal-ingress-controller-leader

  admissionWebhooks:
    createSecretJob:
      resources:
        limits:
          cpu: 250m
          memory: 500Mi
        requests:
          cpu: 100m
          memory: 90Mi

    patchWebhookJob:
      resources:
        limits:
          cpu: 250m
          memory: 500Mi
        requests:
          cpu: 100m
          memory: 90Mi

  resources:
    limits:
      cpu: 250m
      memory: 500Mi
    requests:
      cpu: 100m
      memory: 90Mi

  service:
    create: true
    type: LoadBalancer

    annotations:
      networking.gke.io/load-balancer-type: "Internal"

EOF
  ]
}

data "google_compute_network" "default" {
  name    = "default"
  project = var.project_id
}

resource "google_dns_managed_zone" "internal" {
  count = var.vpn ? 1 : 0

  name        = "internal"
  dns_name    = "internal.${var.dns_name}."
  description = "Private DNS zone for internal applications"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = data.google_compute_network.default.id
    }
  }

  labels = {
    managed_by = "terraform"
  }
}