module "name" {
  source     = "farrukh90/appdeploy/helm"
  name       = "nginx-ingress-controller"
  namespace  = "default"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "nginx-ingress-controller"
  wait       = false

  values = [<<-EOF

replicaCount: 1

  EOF
  ]

}
