module "ingress-ns" {
  source = "farrukh90/ns/kubernetes"
  count  = var.ingress ? 1 : 0
  name   = "ingress"
  annotations = {
    application = "ingress"
  }
  labels = {
    managedby = "terraform"
  }
}


module "ingress" {
  source     = "farrukh90/appdeploy/helm"
  count      = var.ingress ? 1 : 0
  name       = "nginx-ingress-controller"
  namespace  = module.ingress-ns[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "nginx-ingress-controller"
  wait       = false

  values = [<<-EOF

replicaCount: 1

  EOF
  ]

}
