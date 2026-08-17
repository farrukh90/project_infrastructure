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



#Terraform module for deploying an Ingress controller using Helm
module "ingress-terraform-helm" {
  source     = "farrukh90/appdeploy/helm"
  count      = var.ingress ? 1 : 0
  name       = "ingress"
  namespace  = module.ingress-ns[0].name
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  values = [<<EOF
controller:
  # SPRINT-013: allow nginx ingress configuration-snippet annotations. Required
  # for the lab access gate (labs/*-lab/*.tf set a 403/cookie snippet on :8080 +
  # a header check on :9000). Default is false since ingress-nginx v1.9; safe
  # here because only the platform authors lab ingresses, never students.
  allowSnippetAnnotations: true
  # HA for the admission webhook: a SINGLE controller replica means every restart
  # (rollout / config reload / node event) leaves the validating webhook with no
  # endpoints for a few seconds -> ALL lab provisioning fails ("no endpoints
  # available for service ...-admission"). Run >=2 replicas with a zero-gap rollout
  # (surge a new pod, keep both old ones Ready until it is) + a PDB + node spread,
  # so a ready admission endpoint always exists.
  replicaCount: 2
  minReadySeconds: 5
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  podDisruptionBudget:
    enabled: true
    minAvailable: 1
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-nginx
          app.kubernetes.io/component: controller
  admissionWebhooks:
    createSecretJob:
      resources:
        limits:
          cpu: 250m
          memory: 500Mi
        requests:
          cpu: 100m
          memory: 90Mi
    patchWebhookJob:
      resources:
        limits:
          cpu: 250m
          memory: 500Mi
        requests:
          cpu: 100m
          memory: 90Mi
  resources:
    limits:
      cpu: 250m
      memory: 500Mi
    requests:
      cpu: 100m
      memory: 90Mi
  service:
    create: true
    type: LoadBalancer
    loadBalancerSourceRanges: [
        "${var.ingress-controller-config["loadBalancerSourceRanges"]}",
    ]
  EOF
  ]
}

