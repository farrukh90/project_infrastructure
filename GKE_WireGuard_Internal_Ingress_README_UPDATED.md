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

``` text
vpn.awsprojectxconsulting.net
    -> Public NGINX Ingress
    -> wg-easy Web UI :51821

wg.awsprojectxconsulting.net
    -> 35.192.22.36
    -> GCP UDP LoadBalancer :51820
    -> wg-easy

internal-grafana.awsprojectxconsulting.net
    -> 10.128.0.20 when VPN/private mode is enabled
    -> Internal ingress-nginx
    -> Grafana
```

A cleaner future design is:

``` text
Public zone:  awsprojectxconsulting.net
Private zone: internal.awsprojectxconsulting.net
```

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
    cert-manager.io/cluster-issuer: ${var.vpn ? "letsencrypt-internal" : "letsencrypt-prod"}
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

ExternalDNS uses the existing public Cloud DNS zone for both public endpoints
and records that point to private IP addresses.

When VPN is disabled:

``` text
internal-grafana.awsprojectxconsulting.net -> 34.173.145.113
```

When VPN is enabled:

``` text
internal-internal-grafana.awsprojectxconsulting.net -> 10.128.0.20
```

This is intentional for the lab. Students can verify DNS publicly with:

``` bash
dig +short internal-internal-grafana.awsprojectxconsulting.net
nslookup internal-internal-grafana.awsprojectxconsulting.net
```

A successful DNS lookup does not mean the private IP is reachable. Without
WireGuard there is no route to `10.128.0.20`; with WireGuard the route exists.

## 11. End-to-End Grafana Test

Host-routing test:

``` bash
curl -v -H "Host: internal-grafana.awsprojectxconsulting.net" http://10.128.0.20
```

Observed:

``` text
308 Permanent Redirect
Location: https://internal-grafana.awsprojectxconsulting.net
```

HTTPS test:

``` bash
curl -vk https://internal-grafana.awsprojectxconsulting.net
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

## 13. Public DNS with Private IP Addresses

For this lab, keep only the existing public Google Cloud DNS zone:

``` hcl
resource "google_dns_managed_zone" "project" {
  name        = "project"
  dns_name    = "${var.dns_name}."
  description = "Used for project"

  labels = {
    managed_by = "terraform"
  }
}
```

Example records:

``` text
wg.awsprojectxconsulting.net                  -> 35.192.22.36
internal-internal-grafana.awsprojectxconsulting.net   -> 10.128.0.20
internal-prometheus.awsprojectxconsulting.net -> 10.128.0.20
internal-vault.awsprojectxconsulting.net     -> 10.128.0.20
```

Publishing a private IP in public DNS does not expose the application.
WireGuard still provides the required private route.

## Conditional Prometheus Ingress

``` yaml
server:
  ingress:
    enabled: true
    ingressClassName: ${var.vpn ? "internal" : "nginx"}

    annotations:
      cert-manager.io/cluster-issuer: ${var.vpn ? "letsencrypt-internal" : "letsencrypt-prod"}
    hosts:
      - ${var.vpn ? "internal-prometheus" : "prometheus"}.${var.dns_name}

    tls:
      - secretName: ${var.vpn ? "internal-prometheus-tls" : "prometheus-tls"}
        hosts:
          - ${var.vpn ? "internal-prometheus" : "prometheus"}.${var.dns_name}
```

## Conditional Vault Ingress

``` yaml
ingress:
  enabled: true
  ingressClassName: ${var.vpn ? "internal" : "nginx"}

  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    ingress.kubernetes.io/ssl-redirect: "false"
    cert-manager.io/cluster-issuer: ${var.vpn ? "letsencrypt-internal" : "letsencrypt-prod"}

  hosts:
    - host: "${var.vpn ? "internal-vault" : "vault"}.${var.dns_name}"
      http:
        paths:
          - pathType: Prefix
            path: "/"
            backend:
              service:
                name: vault
                port:
                  number: 8200

  tls:
    - secretName: ${var.vpn ? "internal-vault-tls" : "vault-tls"}
      hosts:
        - "${var.vpn ? "internal-vault" : "vault"}.${var.dns_name}"
```

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
dig +short internal-grafana.awsprojectxconsulting.net

curl -v http://10.128.0.20
curl -vk https://internal-grafana.awsprojectxconsulting.net
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

# GKE Public + Private Ingress with WireGuard VPN --- Q&A Study Guide

This guide contains review and interview questions for the architecture
we built: two NGINX Ingress controllers, GKE public/internal
LoadBalancers, WireGuard/wg-easy, split tunneling, ExternalDNS, public
Cloud DNS records pointing to private IPs, cert-manager, and Terraform.

## Architecture and Design

### 1. What problem does an Ingress Controller solve?

An Ingress defines routing rules, but the Ingress Controller implements
them. It receives HTTP/HTTPS traffic, matches host/path rules, handles
TLS, and forwards requests to Kubernetes Services.

### 2. What is the difference between Ingress, IngressClass, and Ingress Controller?

-   **Ingress:** routing rules.
-   **IngressClass:** identifies the controller that should process the
    Ingress.
-   **Ingress Controller:** running software such as ingress-nginx that
    implements those rules.

### 3. Why do we run two ingress-nginx controllers?

One is public (`IngressClass: nginx`) and one is private
(`IngressClass: internal`). This gives us separate public and internal
GCP LoadBalancers.

### 4. What makes the internal controller private?

Its Service is a LoadBalancer with
`networking.gke.io/load-balancer-type: Internal`, so GKE assigns a
private VPC IP such as `10.128.0.20`.

### 5. Why use a separate controller value and election ID?

They distinguish the internal ingress-nginx instance from the public
instance and prevent leader-election/controller ownership conflicts.

### 6. Can both controllers run in the same namespace?

Yes, but separate namespaces make isolation and troubleshooting cleaner.

### 7. What happens if an Ingress has no `ingressClassName`?

Behavior depends on defaults. Explicitly setting the class is safer and
more predictable.

### 8. How does the controller know which Ingress belongs to it?

The Ingress references an IngressClass, which identifies the intended
controller.

## WireGuard and VPN

### 9. Why do we need WireGuard if we already have an internal LoadBalancer?

The internal LoadBalancer has a private IP that a laptop on the public
Internet cannot normally route to. WireGuard provides that private path.

### 10. What is `wg0`?

It is the WireGuard network interface created by wg-easy.

### 11. Why does the server use `10.8.0.1` and the client `10.8.0.2/32`?

`10.8.0.0/24` is the VPN tunnel network. The server uses one address and
each peer receives its own address.

### 12. What does `AllowedIPs` do?

On the client, it determines which destinations are routed through
WireGuard.

### 13. Why did `AllowedIPs = 0.0.0.0/0` make normal Internet stop working?

It routed every IPv4 destination through the VPN, creating a full
tunnel.

### 14. What is split tunneling?

Only selected destinations use the VPN. Everything else uses the normal
Internet connection.

### 15. Why did we use `AllowedIPs = 10.8.0.0/24, 10.128.0.20/32`?

It routes the VPN network and only the internal ingress IP through
WireGuard while normal Internet stays local.

### 16. Why use `/32` for the internal ingress IP?

A `/32` matches exactly one IPv4 address, keeping access tightly scoped.

### 17. What does `PersistentKeepalive = 25` do?

It periodically keeps NAT/firewall state alive, which helps clients
behind NAT.

### 18. Why UDP 51820?

WireGuard is UDP-based, and 51820 is the common/default WireGuard port.

### 19. How do we verify a WireGuard client is connected?

Run:

    POD=$(kubectl get pod -n vpn -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n vpn "$POD" -- wg

Look for a recent `latest handshake` and increasing transfer counters.

### 20. Why did `wg0` initially fail to start?

wg-easy attempted to configure IPv6 while IPv6 was disabled.

### 21. Why did `DISABLE_IPV6=true` fix it?

It prevented wg-easy from configuring unsupported IPv6 settings.

## Kubernetes Services and LoadBalancers

### 22. Why does wg-easy use a ClusterIP plus a separate LoadBalancer?

The web UI is reached through NGINX using the ClusterIP Service. The
separate LoadBalancer exposes only UDP 51820 for WireGuard.

### 23. Why did we split TCP 51821 and UDP 51820?

Our GKE LoadBalancer path rejected the mixed-protocol Service with
`LoadBalancerMixedProtocolNotSupported`.

### 24. What does the `wireguard-udp` Service do?

It creates a public GCP LoadBalancer that forwards UDP 51820 to wg-easy.

### 25. What is the difference between `port`, `targetPort`, and `nodePort`?

-   `port`: Service port.
-   `targetPort`: Pod/container port.
-   `nodePort`: node-level port allocated when applicable.

### 26. Why does WireGuard need a public IP?

Remote clients need a reachable Internet endpoint to establish the
tunnel.

### 27. Why does the internal ingress controller need a private IP?

It is intentionally reachable only through private/VPN routing.

### 28. What is the difference between ClusterIP, NodePort, and LoadBalancer?

-   ClusterIP: cluster-internal.
-   NodePort: exposes a port on nodes.
-   LoadBalancer: asks the cloud provider for a load balancer.

### 29. Who creates the actual GCP LoadBalancer?

GKE's cloud integration sees the Kubernetes LoadBalancer Service and
provisions the Google Cloud resources.

## DNS and ExternalDNS

### 30. What does ExternalDNS do?

It watches Kubernetes Ingresses and Services and synchronizes DNS
records with Google Cloud DNS.

### 31. Does ExternalDNS carry application traffic?

No. It manages DNS records only.

### 32. Does WireGuard require ExternalDNS?

No. A client can use `35.192.22.36:51820` directly. DNS is a
convenience.

### 33. Why do we have `vpn.` and `wg.`?

`vpn.` is the wg-easy web UI. `wg.` is the WireGuard UDP endpoint.

### 34. How does ExternalDNS know an Ingress address?

It reads the Ingress host and LoadBalancer/status information.

### 35. How does ExternalDNS know a Service LoadBalancer address?

It watches the Service and reads the address assigned by GKE.

### 36. What does `external-dns.alpha.kubernetes.io/hostname` do?

It tells ExternalDNS which hostname should point to that Service's
LoadBalancer.

### 37. Can one ExternalDNS deployment watch both Services and Ingresses?

Yes, when configured with both sources.

### 38. Why do we keep internal application records in public DNS?

For teaching. Students can use public DNS tools to verify resolution
separately from VPN/routing.

### 39. Is it valid for public DNS to return `10.128.0.20`?

Yes. DNS can return a private IP.

### 40. Does publishing `10.128.0.20` make Grafana public?

No. Clients still need a route to that private IP.

### 41. What is the difference between DNS resolution and network reachability?

DNS answers "what IP?". Routing answers "can I reach that IP?". They are
separate layers.

### 42. Why can WhatIsMyDNS show the record while the website remains unreachable?

The record is publicly visible, but the returned private IP is not
publicly routable.

### 43. What are ExternalDNS TXT records?

Ownership metadata that helps ExternalDNS track which records it
manages.

### 44. What is DNS TTL?

Time To Live: how long resolvers may cache an answer.

### 45. Why did `dig` show a new IP while `curl` initially used an old one?

Different resolver/cache paths can temporarily hold different values.

### 46. How do we flush DNS cache on macOS?

Run on the Mac:

    sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder

## Conditional Public/Private Applications

### 47. How does this Terraform expression work?

`ingressClassName: ${var.vpn ? "internal" : "nginx"}` renders `internal`
when VPN is true and `nginx` otherwise.

### 48. What happens when `vpn = false`?

Grafana uses the public controller and a hostname such as
`grafana.example.com`.

### 49. What happens when `vpn = true`?

Grafana uses the internal controller and `internal-grafana.example.com`,
which resolves to the private ingress IP.

### 50. Why use `internal-grafana`?

It clearly identifies private access and makes public/private DNS
behavior easy to teach.

### 51. Why change the TLS Secret name too?

The public and internal hostnames have different certificate identities.
Separate Secrets avoid ambiguity.

### 52. Can one Grafana Service have two Ingresses?

Yes. Multiple Ingresses can point to the same Service.

### 53. Could Grafana be public and private simultaneously?

Yes, by creating two Ingress resources.

### 54. Why did we use a Terraform switch instead?

For the lab, `var.vpn` acts as an architecture switch between public and
VPN-only access.

### 55. Can Prometheus and Vault use the same pattern?

Yes. The same conditional IngressClass, hostname, and TLS Secret pattern
applies.

## TLS and cert-manager

### 56. What does cert-manager do?

It automates requesting, renewing, and storing TLS certificates in
Kubernetes Secrets.

### 57. What does Let's Encrypt do?

It is the certificate authority that issues the trusted certificate.

### 58. What is the difference between cert-manager and ingress-nginx?

cert-manager manages certificates. ingress-nginx handles application
traffic and uses the TLS Secret.

### 59. Why did HTTP return `308 Permanent Redirect`?

The Ingress redirected HTTP to HTTPS.

### 60. Why did Grafana return `302 /login`?

Grafana was reached successfully and redirected the unauthenticated
request to its login page.

### 61. What is a Kubernetes TLS Secret?

It contains the certificate and private key used by the Ingress
Controller.

### 62. What is HTTP-01?

An ACME validation method where the certificate authority reaches a
temporary HTTP challenge endpoint.

### 63. Why can HTTP-01 be difficult for a private endpoint?

A public certificate authority normally cannot reach a private
`10.x.x.x` endpoint directly.

### 64. What is DNS-01?

An ACME validation method that proves domain ownership using a DNS TXT
record.

### 65. Why can DNS-01 be better for private applications?

The CA validates DNS ownership rather than connecting to the private
application.

## Terraform

### 66. Why use `count = var.vpn ? 1 : 0`?

It conditionally creates the VPN/private-access resources.

### 67. Why do references use `[0]`?

Resources/modules using `count` become collections. When count is 1, the
first instance is index 0.

### 68. Why did adding `count` make Terraform want to recreate ingress?

The resource address changed from `module.ingress-terraform-helm...` to
`module.ingress-terraform-helm[0]...`.

### 69. What is a Terraform resource address?

The unique path Terraform uses to identify a managed object in
configuration and state.

### 70. What does `terraform state mv` do?

It changes a state address without recreating the real infrastructure.

### 71. Why inspect `terraform plan` carefully?

Structural changes can accidentally plan destruction/recreation of
working resources.

### 72. Why did Terraform try to recreate ExternalDNS even though it was running?

The Helm release existed in Kubernetes but was missing from the current
Terraform state.

### 73. What is the difference between actual Kubernetes resources and Terraform state?

A resource can exist in Kubernetes while Terraform does not know it owns
it. Terraform relies on state rather than automatic discovery.

### 74. When do we use `terraform import`?

When an existing resource needs to be attached to a Terraform resource
address.

### 75. `terraform import` vs `terraform state mv`?

Import brings an existing resource into state. State move
renames/readdresses something already in state.

### 76. Why did a GKE-managed annotation appear as Terraform drift?

Cloud controllers can add operational annotations that are not declared
in Terraform.

### 77. What does `depends_on` do?

It explicitly defines dependency/order between Terraform resources.

### 78. Why use Google Secret Manager?

It provides a managed central location for sensitive values such as the
wg-easy admin password.

### 79. Can sensitive values still exist in Terraform state?

Yes, depending on how the provider/resource/data source is used.
`sensitive` mainly hides normal display; it does not automatically
remove values from state.

## Troubleshooting Scenarios

### 80. DNS resolves to `10.128.0.20`, but curl times out. What do you check?

Check: WireGuard connection, recent handshake, `AllowedIPs`, route to
`10.128.0.20/32`, internal LoadBalancer health, and ingress controller
health.

### 81. `curl http://10.128.0.20` returns NGINX 404. Is that a failure?

No. It proves the path reaches ingress-nginx. The request simply did not
match an Ingress host rule.

### 82. The IP works but the hostname gives 404. What do you check?

Ingress host, Host header, IngressClass, controller ownership/logs, and
backend Service.

### 83. WireGuard connects but normal Internet disappears. Why?

The client likely uses `AllowedIPs = 0.0.0.0/0`. Use split tunneling.

### 84. ExternalDNS is current but the browser reaches an old IP. Why?

Check TTL, OS DNS cache, browser behavior, and compare `dig`,
`nslookup`, `dscacheutil`, and `curl -v`.

### 85. `wg` shows a peer but no `latest handshake`. What does that mean?

The peer exists in configuration, but successful UDP/cryptographic
communication has not occurred. Check endpoint DNS/IP, UDP 51820,
LoadBalancer, NAT/firewall, and client activation.

### 86. Why was an NGINX 404 useful?

It proved: Laptop -\> WireGuard -\> internal LoadBalancer -\>
ingress-nginx.

### 87. Why was the 308 redirect useful?

It proved the request matched the intended Ingress host and NGINX
redirected it to HTTPS.

### 88. Why was `302 /login` the final success signal?

It was an application-level Grafana response, proving the full path
reached Grafana.

## End-to-End Walkthrough

### 89. What happens when a user opens `https://internal-grafana.awsprojectxconsulting.net` while WireGuard is connected?

``` text
Browser
   |
   v
Public DNS lookup
   |
   v
internal-grafana... -> 10.128.0.20
   |
   v
Mac routing table
   |
   v
AllowedIPs matches 10.128.0.20/32
   |
   v
WireGuard tunnel
   |
   v
wg-easy in GKE
   |
   v
GCP VPC
   |
   v
Internal GCP LoadBalancer
   |
   v
internal ingress-nginx
   |
   v
Ingress host/path rule
   |
   v
Grafana Service
   |
   v
Grafana Pod
   |
   v
HTTPS response / redirect to /login
```

If WireGuard is disconnected, DNS can still resolve
`internal-grafana...` to `10.128.0.20`, but the laptop has no route to
the private address, so the application is unavailable.

## Quick Review Commands

``` bash
kubectl get ingressclass
kubectl get svc -A | grep LoadBalancer
kubectl get svc -n vpn
kubectl get svc -n internal-ingress

POD=$(kubectl get pod -n vpn -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n vpn "$POD" -- wg

dig +short wg.awsprojectxconsulting.net
dig +short internal-grafana.awsprojectxconsulting.net

curl -v http://10.128.0.20
curl -vk https://internal-grafana.awsprojectxconsulting.net
```

## Core Lesson

``` text
DNS tells us WHERE.
Routing tells us WHETHER WE CAN GET THERE.
WireGuard provides the private route.
The LoadBalancer provides the entry point.
IngressClass chooses the controller.
Ingress chooses the Service.
The Service chooses the Pods.
cert-manager provides TLS.
ExternalDNS keeps DNS synchronized.
```
