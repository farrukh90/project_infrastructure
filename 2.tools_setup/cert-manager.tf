module "cert-manager-ns" {
  source = "farrukh90/ns/kubernetes"
  name   = "cert-manager"

  annotations = {
    application = "cert-manager"
  }

  labels = {
    managedby = "terraform"
  }
}

module "cert-mananger-terraform-helm" {
  source = "farrukh90/release/helm"

  deployment_name      = "cert-manager"
  deployment_namespace = module.cert-manager-ns.name
  chart                = "cert-manager"
  chart_version        = var.cert-manager-config["chart_version"]
  repository           = "https://charts.jetstack.io"

  values_yaml = <<EOF
global:
  leaderElection:
    namespace: cert-manager

crds:
  enabled: true
EOF
}

resource "null_resource" "letsencrypt_prod" {
  depends_on = [
    module.cert-mananger-terraform-helm
  ]

  triggers = {
    email = var.email
  }

  provisioner "local-exec" {
    command = <<EOF
kubectl apply -f - <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${var.email}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
YAML
EOF
  }
}