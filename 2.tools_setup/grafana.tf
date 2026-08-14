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
  name       = "grafana"
  namespace  = module.grafana-ns[0].name
  chart      = "grafana"
  repository = "https://grafana-community.github.io/helm-charts"
  values = [<<EOF


ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    kubernetes.io/ingress.class: nginx
    kubernetes.io/tls-acme: "true"
  path: /
  pathType: Prefix

  hosts:
    - grafana.${var.dns_name}
  ## Extra paths to prepend to every host configuration. This is useful when working with annotation based services.
  extraPaths: []
  # - path: /*
  #   pathType: Prefix
  #   backend:
  #     service:
  #       name: ssl-redirect
  #       port:
  #         name: use-annotation



EOF
  ]
}
