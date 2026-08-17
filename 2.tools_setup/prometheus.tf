module "prometheus-ns" {
  source = "farrukh90/ns/kubernetes"
  count  = var.prometheus ? 1 : 0
  name   = "prometheus"

  annotations = {
    application = "prometheus"
  }

  labels = {
    managedby = "terraform"
  }
}

module "prometheus-terraform-helm" {
  source     = "farrukh90/appdeploy/helm"
  name       = "prometheus"
  namespace  = module.prometheus-ns[0].name
  chart      = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"

  values = [<<EOF
  
server:
  ingress:
    enabled: true

    ingressClassName: ${var.vpn ? "internal" : "nginx"}

    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      acme.cert-manager.io/http01-edit-in-place: "true"

    hosts:
      - ${var.vpn ? "internal-prometheus" : "prometheus"}.${var.dns_name}

    tls:
      - secretName: ${var.vpn ? "internal-prometheus-tls" : "prometheus-tls"}
        hosts:
          - ${var.vpn ? "internal-prometheus" : "prometheus"}.${var.dns_name}
EOF
  ]
}