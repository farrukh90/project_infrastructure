# Create a Kubernetes namespace for Cert-Manager
module "cert-manager-terraform-k8s-namespace" {
  source    = "farrukh90/namespace/kubernetes"
  version   = "0.0.11"
  pod_limit = 1000
  name      = "cert-manager"
  labels = {
    environment = "dev"
  }
  annotations = {
    managed_by = "terraform"
  }
}

# Deploy Cert-Manager using Helm into the Grafana namespace
module "cert-mananger-terraform-helm" {
  source = "farrukh90/release/helm"

  deployment_name      = "cert-manager"
  deployment_namespace = module.cert-manager-terraform-k8s-namespace.name
  chart                = "cert-manager"
  chart_version        = var.cert-manager-config["chart_version"]
  repository           = "https://charts.jetstack.io"
  values_yaml          = <<EOF
global:
  leaderElection:
    namespace: cert-manager

crds:
  enabled: true
EOF
}

resource "kubernetes_manifest" "letsencrypt_prod" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"

    metadata = {
      name = "letsencrypt-prod"
    }

    spec = {
      acme = {
        email  = var.email
        server = "https://acme-v02.api.letsencrypt.org/directory"

        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }

        solvers = [
          {
            http01 = {
              ingress = {
                ingressClassName = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [
    module.cert-mananger-terraform-helm
  ]
}
