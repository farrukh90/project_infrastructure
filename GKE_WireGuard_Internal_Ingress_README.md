# GKE Public + Private Ingress with WireGuard VPN

## Goal

Build a GKE architecture where normal applications can use a public
NGINX Ingress, while private applications can use a second internal
NGINX Ingress that is reachable from a laptop only through WireGuard.

## Final Architecture

``` text
                                      INTERNET
                                         |
              +--------------------------+--------------------------+
              |                                                     |
              | HTTPS                                               | UDP 51820
              v                                                     v
     Public GCP LoadBalancer                              WireGuard GCP LoadBalancer
        34.173.145.113                                        35.192.22.36
              |                                                     |
              v                                                     v
     Public ingress-nginx                                      wireguard-udp
       IngressClass: nginx                                          |
              |                                                     v
              |                                                  wg-easy
              |                                                wg0: 10.8.0.1
              |                                                     ^
              |                                                VPN tunnel
              |                                                     |
              |                                                   Laptop
              |                                              10.8.0.2/32
              |
              +---------------------- public apps

                                      GCP VPC
                                         |
                                         v
                              Internal GCP LoadBalancer
                                    10.128.0.20
                                         |
                                         v
                              Internal ingress-nginx
                               IngressClass: internal
                                         |
                              +----------+----------+
                              |                     |
                              v                     v
                           Grafana              Other private
                           Service                  Services
                              |                     |
                              v                     v
                            Pods                  Pods
```

Split tunnel:

``` text
Normal Internet -----------------------------> normal Wi-Fi / ISP
10.8.0.0/24 --------------------------------> WireGuard
10.128.0.20/32 -----------------------------> WireGuard -> Internal Ingress
```

## DNS Layout

```text
vpn.awsprojectxconsulting.net
    -> Public NGINX Ingress
    -> wg-easy Web UI :51821

wg.awsprojectxconsulting.net
    -> 35.192.22.36
    -> GCP UDP LoadBalancer :51820
    -> wg-easy

When VPN is disabled:

grafana.awsprojectxconsulting.net
    -> Public ingress-nginx
    -> Public LoadBalancer

When VPN is enabled:

internal-grafana.awsprojectxconsulting.net
    -> 10.128.0.20
    -> Internal ingress-nginx
    -> Grafana

## 1. VPN Namespace

``` hcl
module "vpn-ns" {
  source = "farrukh90/ns/kubernetes"
  count  = var.vpn ? 1 : 0

  name = "vpn"

  annotations = {
    application = "wireguard"
  }

  labels = {
    managedby = "terraform"
  }
}
```

## 2. Generate and Store the wg-easy Admin Password

``` hcl
resource "random_password" "wireguard_admin_password" {
  count   = var.vpn ? 1 : 0
  length  = 24
  special = false
}

resource "google_secret_manager_secret" "wireguard_admin_password" {
  count     = var.vpn ? 1 : 0
  secret_id = "wireguard-admin-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "wireguard_admin_password" {
  count       = var.vpn ? 1 : 0
  secret      = google_secret_manager_secret.wireguard_admin_password[0].id
  secret_data = random_password.wireguard_admin_password[0].result
}

data "google_secret_manager_secret_version" "wireguard_admin_password" {
  count   = var.vpn ? 1 : 0
  project = var.project_id
  secret  = google_secret_manager_secret.wireguard_admin_password[0].secret_id

  depends_on = [
    google_secret_manager_secret_version.wireguard_admin_password
  ]
}
```

Retrieve it with:

``` bash
gcloud secrets versions access latest --secret="wireguard-admin-password" --project="$GOOGLE_CLOUD_PROJECT"
```

## 3. Deploy wg-easy

We first tested `wg-access-server`, but its old Helm chart rendered
`networking.k8s.io/v1beta1` Ingress objects. Modern GKE rejected that
API, so we switched to `wg-easy`.

``` hcl
module "wireguard-terraform-helm" {
  source = "farrukh90/appdeploy/helm"
  count  = var.vpn ? 1 : 0

  name       = "wireguard"
  namespace  = module.vpn-ns[0].name
  chart      = "wg-easy"
  repository = "https://raw.githubusercontent.com/hansehe/wg-easy-helm/master/helm/charts"

  values = [<<EOF

environmentVariables:
  INSECURE: "true"
  DISABLE_IPV6: "true"
  INIT_ENABLED: "true"
  INIT_USERNAME: "admin"
  INIT_PASSWORD: "${trimspace(data.google_secret_manager_secret_version.wireguard_admin_password[0].secret_data)}"
  INIT_HOST: "wg.${var.dns_name}"
  INIT_PORT: "51820"

securityContext:
  privileged: true
  allowPrivilegeEscalation: true
  capabilities:
    add:
      - NET_ADMIN
      - SYS_MODULE

service:
  type: ClusterIP
  port: 51821

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: vpn.${var.dns_name}
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: wireguard-web-tls
      hosts:
        - vpn.${var.dns_name}

volume:
  enabled: true
  size: 1Gi

EOF
  ]
}
```

### IPv6 Fix

`wg0` initially failed with:

``` text
Error: ipv6: IPv6 is disabled on this device.
```

The fix was:

``` yaml
DISABLE_IPV6: "true"
```

Verify:

``` bash
POD=$(kubectl get pod -n vpn -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n vpn "$POD" -- ip link show wg0
```

## 4. Separate UDP 51820 from the Web UI

GKE rejected one LoadBalancer containing both `51820/UDP` and
`51821/TCP`.

The Helm Service stays `ClusterIP`. A separate UDP-only LoadBalancer
exposes WireGuard:

``` hcl
resource "kubernetes_service_v1" "wireguard_udp" {
  count = var.vpn ? 1 : 0

  metadata {
    name      = "wireguard-udp"
    namespace = module.vpn-ns[0].name

    annotations = {
      "external-dns.alpha.kubernetes.io/hostname" = "wg.${var.dns_name}"
    }
  }

  spec {
    selector = {
      "app.kubernetes.io/instance" = "wireguard"
      "app.kubernetes.io/name"     = "wg-easy"
    }

    port {
      name        = "wireguard"
      port        = 51820
      target_port = 51820
      protocol    = "UDP"
    }

    type = "LoadBalancer"
  }

  depends_on = [
    module.wireguard-terraform-helm
  ]
}
```

Observed public WireGuard endpoint:

``` text
35.192.22.36:51820/UDP
```

## 5. WireGuard Client

Use the WireGuard client, not OpenVPN.

The generated profile initially used:

``` ini
AllowedIPs = 0.0.0.0/0, ::/0
```

That created a full tunnel and caused the laptop to lose normal Internet
access.

We changed it to split tunneling:

``` ini
[Interface]
Address = 10.8.0.2/32
DNS = 1.1.1.1
MTU = 1420

[Peer]
AllowedIPs = 10.8.0.0/24, 10.128.0.20/32
Endpoint = 35.192.22.36:51820
PersistentKeepalive = 25
```

After DNS is stable, the endpoint can be:

``` ini
Endpoint = wg.awsprojectxconsulting.net:51820
```

## 6. Verify WireGuard

``` bash
POD=$(kubectl get pod -n vpn -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n vpn "$POD" -- wg
```

Success includes:

``` text
latest handshake: ...
transfer: ...
```

## 7. Internal Ingress Controller

The internal ingress is part of the VPN/private-access feature:

``` hcl
module "internal-ingress-ns" {
  source = "farrukh90/ns/kubernetes"
  count  = var.vpn ? 1 : 0
  name   = "internal-ingress"

  annotations = {
    application = "internal-ingress"
  }

  labels = {
    managedby = "terraform"
  }
}
```

``` hcl
module "internal-ingress-terraform-helm" {
  source = "farrukh90/appdeploy/helm"
  count  = var.vpn ? 1 : 0

  name       = "internal-ingress"
  namespace  = module.internal-ingress-ns[0].name
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"

  values = [<<EOF
controller:
  allowSnippetAnnotations: true
  replicaCount: 2
  minReadySeconds: 5

  ingressClassResource:
    name: internal
    enabled: true
    default: false
    controllerValue: k8s.io/internal-ingress-nginx

  ingressClass: internal
  electionID: internal-ingress-controller-leader

  service:
    create: true
    type: LoadBalancer
    annotations:
      networking.gke.io/load-balancer-type: "Internal"

EOF
  ]
}
```

Observed internal LB:

``` text
10.128.0.20
```

## 8. Test Internal Ingress

From the VPN-connected laptop:

``` bash
curl -v http://10.128.0.20
```

An NGINX `404 Not Found` is a successful networking test. It proves:

``` text
Laptop -> WireGuard -> GKE -> Internal LoadBalancer -> internal ingress-nginx
```

## 9. Switch Grafana Based on `var.vpn`

One Grafana deployment can dynamically select the controller:

``` hcl
ingressClassName: ${var.vpn ? "internal" : "nginx"}
```

Example:

``` hcl
ingress:
  enabled: true
  ingressClassName: ${var.vpn ? "internal" : "nginx"}

  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    ingress.kubernetes.io/ssl-redirect: "false"
    cert-manager.io/cluster-issuer: letsencrypt-prod
    acme.cert-manager.io/http01-edit-in-place: "true"

  hosts:
    - grafana.${var.dns_name}

  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.${var.dns_name}
```

Behavior:

``` text
vpn = false -> nginx    -> public LB
vpn = true  -> internal -> private LB -> VPN required
```

## 10. ExternalDNS

ExternalDNS automatically changed Grafana from the public address to the
private address:

``` text
OLD: grafana.awsprojectxconsulting.net -> 34.173.145.113
NEW: grafana.awsprojectxconsulting.net -> 10.128.0.20
```

Verify:

``` bash
dig +short grafana.awsprojectxconsulting.net
```

In private mode:

``` text
10.128.0.20
```

## 11. End-to-End Grafana Test

Host-routing test:

``` bash
curl -v -H "Host: grafana.awsprojectxconsulting.net" http://10.128.0.20
```

Observed:

``` text
308 Permanent Redirect
Location: https://grafana.awsprojectxconsulting.net
```

HTTPS test:

``` bash
curl -vk https://grafana.awsprojectxconsulting.net
```

Observed:

``` text
IPv4: 10.128.0.20
SSL certificate verify ok
HTTP/2 302
location: /login
```

With WireGuard disconnected, Grafana became unavailable. That is the
intended behavior.

## 12. cert-manager

The existing Let's Encrypt certificate remained valid.

For a long-term private-only hostname, DNS-01 is preferable to HTTP-01
because a public ACME server cannot directly reach a private `10.x.x.x`
load balancer.

## 13. Optional Private Cloud DNS Zone

The cluster uses the default VPC:

``` hcl
data "google_compute_network" "default" {
  name    = "default"
  project = var.project_id
}

resource "google_dns_managed_zone" "internal" {
  count = var.vpn ? 1 : 0

  name        = "internal"
  dns_name    = "internal.${var.dns_name}."
  description = "Private DNS zone for internal applications"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = data.google_compute_network.default.id
    }
  }

  labels = {
    managed_by = "terraform"
  }
}
```

Important: `DNS = 1.1.1.1` cannot resolve a Google Cloud private DNS
zone. Before moving internal records exclusively to the private zone,
provide VPN clients a DNS resolver that can query that zone.

## 14. Terraform State Lesson

Adding `count` changes an existing module address.

Before:

``` text
module.ingress-terraform-helm.helm_release.this
```

After:

``` text
module.ingress-terraform-helm[0].helm_release.this
```

Move the state instead of destroying/recreating:

``` bash
terraform state mv   'module.ingress-terraform-helm.helm_release.this'   'module.ingress-terraform-helm[0].helm_release.this'
```

## 15. Useful Commands

``` bash
kubectl get pods -n vpn -o wide
kubectl get svc -n vpn -o wide
kubectl get ingress -n vpn

POD=$(kubectl get pod -n vpn -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n vpn "$POD" -- wg
kubectl exec -n vpn "$POD" -- ip link show wg0

kubectl get ingressclass
kubectl get svc -n internal-ingress
kubectl get svc -A | grep LoadBalancer

kubectl get ingress -n grafana -o wide
kubectl describe ingress -n grafana grafana

dig +short wg.awsprojectxconsulting.net
dig +short grafana.awsprojectxconsulting.net

curl -v http://10.128.0.20
curl -vk https://grafana.awsprojectxconsulting.net
```

## 16. Mental Model

``` text
DNS
 -> tells the client which IP to use

WireGuard
 -> gives the laptop a private path

AllowedIPs
 -> decides which destinations use the VPN

Internal GCP LoadBalancer
 -> gives the private ingress controller a VPC address

IngressClass
 -> decides which controller owns an Ingress

Ingress
 -> maps host/path to a Service

Service
 -> routes to application Pods

ExternalDNS
 -> synchronizes Kubernetes hosts/services with Cloud DNS

cert-manager
 -> manages TLS certificates
```

## Result

The completed design provides:

``` text
Public apps  -> Public ingress-nginx -> Internet
Private apps -> Internal ingress-nginx -> WireGuard required
```

Grafana was successfully tested through:

``` text
Laptop
 -> WireGuard
 -> 10.128.0.20
 -> Internal ingress-nginx
 -> Grafana Service
 -> Grafana Pod
 -> HTTPS /login
```
