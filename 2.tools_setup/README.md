# Enable SSL/TLS for Kubernetes Deployments with cert-manager and Let's Encrypt

This guide explains how to update an existing Kubernetes application so it can receive a trusted Let's Encrypt TLS certificate through cert-manager.

## Prerequisites

Your cluster should already have:

- cert-manager installed
- a `ClusterIssuer` named `letsencrypt-prod`
- an Ingress controller
- public DNS pointing your application hostname to the Ingress controller

Verify cert-manager:

```bash
kubectl get pods -n cert-manager
```

Verify the ClusterIssuer:

```bash
kubectl get clusterissuer letsencrypt-prod
```

The issuer should show:

```text
READY   True
```

## What needs to change in each application

You normally do **not** need to change the Kubernetes `Deployment` itself.

SSL/TLS is terminated at the Ingress layer, so you mainly update the application's `Ingress`.

The Ingress needs:

1. The cert-manager ClusterIssuer annotation.
2. An `ingressClassName`.
3. A `tls` section containing the hostname and TLS secret name.
4. A matching hostname under `rules`.

## Example application

Assume your application already has a Service named:

```text
my-app
```

running on port:

```text
80
```

and you want it available at:

```text
app.example.com
```

Use an Ingress similar to this:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

spec:
  ingressClassName: nginx

  tls:
    - hosts:
        - app.example.com
      secretName: my-app-tls

  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

Replace:

```text
app.example.com
```

with the real hostname for the application.

Replace:

```text
my-app
```

with the Kubernetes Service name.

The TLS secret name can be any valid Kubernetes Secret name, for example:

```text
my-app-tls
```

cert-manager will create and manage that Secret automatically.

## Important fields

### ClusterIssuer annotation

Add:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
```

This tells cert-manager to request the certificate using the cluster-wide Let's Encrypt issuer.

### Ingress class

For an NGINX-based IngressClass named `nginx`:

```yaml
spec:
  ingressClassName: nginx
```

Confirm the available IngressClasses with:

```bash
kubectl get ingressclass
```

If your cluster uses another class, replace `nginx` with that class name.

## TLS section

Add:

```yaml
tls:
  - hosts:
      - app.example.com
    secretName: my-app-tls
```

The hostname should match the hostname under `rules`.

For example:

```yaml
tls:
  - hosts:
      - grafana.example.com
    secretName: grafana-tls

rules:
  - host: grafana.example.com
```

## Full Deployment + Service + Ingress example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - containerPort: 80

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
spec:
  selector:
    app: nginx-demo
  ports:
    - port: 80
      targetPort: 80

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-demo
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx

  tls:
    - hosts:
        - nginx.example.com
      secretName: nginx-demo-tls

  rules:
    - host: nginx.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-demo
                port:
                  number: 80
```

Apply it:

```bash
kubectl apply -f deployment.yaml
```

## Helm chart example

If your application is deployed with Helm, values can look like:

```yaml
ingress:
  enabled: true

  className: nginx

  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

  hosts:
    - host: app.example.com
      paths:
        - path: /
          pathType: Prefix

  tls:
    - secretName: my-app-tls
      hosts:
        - app.example.com
```

The exact Helm values depend on the chart. Check the application's `values.yaml` because field names may differ between charts.

## Terraform Helm example

If Terraform is deploying the Helm chart:

```hcl
values_yaml = <<EOF
ingress:
  enabled: true

  className: nginx

  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

  hosts:
    - host: app.example.com
      paths:
        - path: /
          pathType: Prefix

  tls:
    - secretName: my-app-tls
      hosts:
        - app.example.com
EOF
```

## DNS requirement

Before Let's Encrypt can issue an HTTP-01 certificate, the hostname must resolve publicly to the Ingress controller.

Check:

```bash
nslookup app.example.com
```

or:

```bash
dig app.example.com
```

Then compare it with the Ingress address:

```bash
kubectl get ingress
```

and, if your Ingress controller uses a `LoadBalancer` Service:

```bash
kubectl get svc -A
```

If ExternalDNS manages DNS records, make sure the application's Ingress has the ExternalDNS configuration required by your environment.

## Verify certificate creation

After deploying the updated Ingress:

```bash
kubectl get ingress
```

Then:

```bash
kubectl get certificate
```

You should eventually see:

```text
NAME         READY   SECRET
my-app-tls   True    my-app-tls
```

Check the TLS Secret:

```bash
kubectl get secret my-app-tls
```

The Secret should have type:

```text
kubernetes.io/tls
```

## Troubleshooting

### Check the ClusterIssuer

```bash
kubectl get clusterissuer
```

Detailed information:

```bash
kubectl describe clusterissuer letsencrypt-prod
```

### Check certificates

```bash
kubectl get certificate -A
```

Detailed information:

```bash
kubectl describe certificate my-app-tls
```

### Check certificate requests

```bash
kubectl get certificaterequest -A
```

### Check ACME orders

```bash
kubectl get orders -A
```

### Check ACME challenges

```bash
kubectl get challenges -A
```

Detailed challenge information:

```bash
kubectl describe challenge -A
```

### Check cert-manager logs

```bash
kubectl logs -n cert-manager deployment/cert-manager
```

### Useful one-liner

To quickly inspect the Let's Encrypt workflow:

```bash
kubectl get clusterissuer,certificate,certificaterequest,order,challenge -A
```

## Common problems

### ClusterIssuer is not ready

Check:

```bash
kubectl describe clusterissuer letsencrypt-prod
```

Do not troubleshoot the application certificate until the issuer is ready.

### DNS points to the wrong address

Let's Encrypt HTTP-01 validation must be able to reach the hostname from the public internet.

Verify:

```bash
dig +short app.example.com
```

and compare it to the public address of your Ingress controller.

### Wrong IngressClass

Check:

```bash
kubectl get ingressclass
```

Then update:

```yaml
ingressClassName: nginx
```

to the correct class.

### Certificate remains Pending

Run:

```bash
kubectl get certificate,certificaterequest,order,challenge -A
```

Then inspect the failing resource with `kubectl describe`.

### TLS Secret does not exist

Do not manually create the TLS Secret when cert-manager is managing the certificate.

The Ingress specifies:

```yaml
secretName: my-app-tls
```

and cert-manager creates that Secret after successful certificate issuance.

## Standard template for new applications

Use this as the basic Ingress template:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: APPLICATION_NAME
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

spec:
  ingressClassName: nginx

  tls:
    - hosts:
        - APPLICATION_DOMAIN
      secretName: APPLICATION_NAME-tls

  rules:
    - host: APPLICATION_DOMAIN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: APPLICATION_SERVICE
                port:
                  number: APPLICATION_SERVICE_PORT
```

Replace:

```text
APPLICATION_NAME
APPLICATION_DOMAIN
APPLICATION_SERVICE
APPLICATION_SERVICE_PORT
```

with the application's real values.

## Expected flow

```text
User
  |
  | HTTPS
  v
Application DNS
  |
  v
Ingress Controller
  |
  +---- cert-manager annotation
  |
  v
Let's Encrypt HTTP-01 validation
  |
  v
Certificate issued
  |
  v
Kubernetes TLS Secret
  |
  v
Ingress serves HTTPS
  |
  v
Kubernetes Service
  |
  v
Application Pods
```

Once the certificate is issued, cert-manager automatically manages renewal. You should not need to manually renew application certificates.
