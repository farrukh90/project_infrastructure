module "vault-ns" {
  source = "farrukh90/ns/kubernetes"
  count  = var.vault ? 1 : 0
  name   = "vault"
  annotations = {
    application = "vault"
  }
  labels = {
    managedby = "terraform"
  }
}

# Deploy Vault using Helm into the Vault namespace
module "vault-terraform-helm" {
  source     = "farrukh90/appdeploy/helm"
  count      = var.vault ? 1 : 0
  name       = "vault"
  namespace  = module.vault-ns[0].name
  chart      = "vault"
  repository = "https://helm.releases.hashicorp.com"
  values = [<<EOF
# Add Vault configuration settings here

global:
  # enabled is the master enabled switch. Setting this to true or false
  # will enable or disable all the components within this chart by default.
  enabled: true

server:
  resources:
    requests:
      memory: 128Mi
      cpu: 128m
    limits:
      memory: 256Mi
      cpu: 250m
  readinessProbe:
    enabled: false
  annotations:
    prometheus.io/scrape: "true"

  ingress:
    enabled: true
    ingressClassName: ${var.vpn ? "internal-nginx" : "nginx"}
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
      ingress.kubernetes.io/ssl-redirect: "false"
      cert-manager.io/cluster-issuer: ${var.vpn ? "letsencrypt-internal" : "letsencrypt-prod"}
    hosts:
      - host: "${var.vpn ? "internal-vault" : "vault"}.${var.dns_name}"
        http:
          paths:
            - pathType: Prefix
              path: "/"
              backend:
                service:
                  name: vault
                  port:
                    number: 8200

    tls:
      - secretName: ${var.vpn ? "internal-vault-tls" : "vault-tls"}
        hosts:
          - "${var.vpn ? "internal-vault" : "vault"}.${var.dns_name}"
EOF
  ]
}
