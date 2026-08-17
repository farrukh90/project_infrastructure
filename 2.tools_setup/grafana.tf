module "grafana-ns" {
  source = "farrukh90/ns/kubernetes"
  count  = var.grafana ? 1 : 0
  name   = "grafana"
  annotations = {
    application = "grafana"
  }
  labels = {
    managedby = "terraform"
  }
}

# Deploy Grafana using Helm into the Grafana namespace
module "grafana-terraform-helm" {
  source     = "farrukh90/appdeploy/helm"
  count      = var.grafana ? 1 : 0
  name       = "grafana"
  namespace  = module.grafana-ns[0].name
  chart      = "grafana"
  repository = "https://grafana-community.github.io/helm-charts"
  values = [<<EOF


ingress:
  enabled: true
  ingressClassName: ${var.vpn ? "internal-nginx" : "nginx"}
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    ingress.kubernetes.io/ssl-redirect: "false"
    cert-manager.io/cluster-issuer: ${var.vpn ? "letsencrypt-internal" : "letsencrypt-prod"}
  path: /
  pathType: Prefix

  hosts:
    - ${var.vpn ? "internal-grafana" : "grafana"}.${var.dns_name}

  tls:
    - secretName: ${var.vpn ? "internal-grafana-tls" : "grafana-tls"}
      hosts:
        - ${var.vpn ? "internal-grafana" : "grafana"}.${var.dns_name}
EOF
  ]
}
