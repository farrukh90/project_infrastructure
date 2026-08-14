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
EOF
  ]
}
