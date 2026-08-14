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

# Deploy prometheus using Helm into the prometheus namespace
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
    ingressClassName: "nginx"
    annotations:
      kubernetes.io/ingress.class: nginx
      kubernetes.io/tls-acme: 'true'
    hosts: 
      - prometheus.${var.dns_name}
EOF
  ]
}
