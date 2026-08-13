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
  source = "farrukh90/release/helm"

  deployment_name      = "vault"
  deployment_namespace = module.vault-ns[0].name
  chart                = "vault"
  chart_version        = var.vault-config["chart_version"]
  repository           = "https://helm.releases.hashicorp.com"
  values_yaml          = <<EOF
# Add Vault configuration settings here

global:
  # enabled is the master enabled switch. Setting this to true or false
  # will enable or disable all the components within this chart by default.
  enabled: true

server:
  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: 500m
  readinessProbe:
    enabled: false
  annotations:
    prometheus.io/scrape: "true"

  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "0"
      ingress.kubernetes.io/ssl-redirect: "false"
      cert-manager.io/cluster-issuer: letsencrypt-prod
      acme.cert-manager.io/http01-edit-in-place: "true"
    ingressClassName: "nginx"
    hosts:
    - host: "vault.${var.dns_name}"
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
      - secretName: vault-tls
        hosts:
          - "vault.${var.dns_name}"
EOF
}
