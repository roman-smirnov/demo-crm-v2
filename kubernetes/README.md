# Kubernetes App Deployment Instructions

This repo deploys:
- `demo-crm` (Next.js app) as a Deployment + Service (ClusterIP when exposing via Ingress)
- MongoDB via the `bitnami/mongodb` Helm chart
- Optional NGINX Ingress Controller via Helm

All manifests are under `./kubernetes/manifests/`. Helm values live under `./kubernetes/helm/`. Helper scripts live under `./kubernetes/scripts/`.

## Prerequisites
- A running Kubernetes cluster (GKE or any other)
- `kubectl` configured to talk to the cluster
- `helm` installed
- (GKE only) `gcloud` if you use the helper scripts

Verify access:
```bash
kubectl get nodes
```

## Quick start (script)
Fill in the MongoDB auth + connection files:
- `kubernetes/helm/mongodb_values.yaml` (base values)
- `kubernetes/helm/mongodb_values_override.yaml` (overrides; sets `auth.existingSecret: demo-mongo-auth`)
- `creds/mongodb_auth.env` (Bitnami auth keys)
- `creds/mongo.env` (`MONGODB_URI`)

Then run:
```bash
./kubernetes/scripts/deploy.sh
```

If you want to run the steps manually, follow the sections below.

## Tear down (script)
Remove the app resources:
```bash
./kubernetes/scripts/tear_down.sh
```

Remove the app Secret too:
```bash
DELETE_SECRETS=1 ./kubernetes/scripts/tear_down.sh
```

## 1) Install MongoDB with Helm
Create or update `kubernetes/helm/mongodb_values.yaml` and `kubernetes/helm/mongodb_values_override.yaml`. Ensure the combined values configure:
- 2 replicas
- persistence enabled
- authentication enabled with `auth.existingSecret: demo-mongo-auth`

Create `creds/mongodb_auth.env` (example keys):
```bash
mongodb-root-password=change-me-root
mongodb-passwords=change-me-app
mongodb-replica-set-key=change-me-repl
```

Create the Secret:
```bash
kubectl create secret generic demo-mongo-auth \
  --from-env-file=creds/mongodb_auth.env \
  --dry-run=client -o yaml | kubectl apply -f -
```

Install the chart (default namespace, release name `demo-mongo`):
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install demo-mongo bitnami/mongodb \
  -f kubernetes/helm/mongodb_values.yaml \
  -f kubernetes/helm/mongodb_values_override.yaml
```

Find service/pod DNS names to build your connection string:
```bash
kubectl get svc | rg demo-mongo
kubectl get pods | rg demo-mongo
```

## 2) Create the MONGODB_URI Secret
The app reads `MONGODB_URI` from a Secret named `demo-crm-mongodb-uri`.

Edit `creds/mongo.env` (single line):
```bash
MONGODB_URI="mongodb://<user>:<pass>@<host1>,<host2>/demo-crm?authSource=<auth-db>&replicaSet=<rs-name>"
```

Create or update the Secret:
```bash
kubectl create secret generic demo-crm-mongodb-uri \
  --from-env-file=creds/mongo.env \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 3) Deploy the demo-crm application
Apply ConfigMap, Deployment, and Service:
```bash
kubectl apply -f kubernetes/manifests/app/configmap.yaml
kubectl apply -f kubernetes/manifests/app/deployment.yaml
kubectl apply -f kubernetes/manifests/app/service.yaml
```

Wait for the Deployment:
```bash
kubectl rollout status deployment/demo-crm
kubectl get pods -l app=demo-crm -o wide
```

## 4) Ingress (optional, recommended for this task)
The app Service should be `ClusterIP` (see `kubernetes/manifests/app/service.yaml`).

Install the F5 NGINX Ingress Controller in its own namespace and set its
IngressClass as the default so you can omit `ingressClassName` in app Ingresses:
```bash
kubectl create namespace nginx-ingress

helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update

helm install nginx-ingress nginx-stable/nginx-ingress -n nginx-ingress \
  --set controller.ingressClass.name=nginx \
  --set controller.ingressClass.create=true \
  --set controller.ingressClass.setAsDefaultIngress=true
```

If you do not set the default IngressClass, add `spec.ingressClassName: nginx`
to `kubernetes/manifests/app/ingress.yaml`.

Confirm the default IngressClass:
```bash
kubectl get ingressclass
```

Note: The F5 NGINX Ingress Controller uses `nginx.org/*` annotations (not
`nginx.ingress.kubernetes.io/*`).

Create the app Ingress (replace `demo-crm.example.com` in
`kubernetes/manifests/app/ingress.yaml` with your hostname):
```bash
kubectl apply -f kubernetes/manifests/app/ingress.yaml
```

Get the Ingress Controller external address and point your DNS A record (or AWS
CNAME) at it:
```bash
kubectl get svc -n nginx-ingress
```

## 5) SSL termination (bonus: Let's Encrypt via cert-manager)
cert-manager is the Helm chart used to automate Let's Encrypt certificates.
Install cert-manager via Helm (includes CRDs):
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true
```

Wait for cert-manager and confirm CRDs:
```bash
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
kubectl get crds | rg cert-manager
```

Create the ClusterIssuer (edit the email in
`kubernetes/manifests/app/clusterissuer.yaml` first):
```bash
kubectl apply -f kubernetes/manifests/app/clusterissuer.yaml
```

Ensure your DNS record points at the Ingress controller before requesting the certificate.

Re-apply the Ingress to request the certificate:
```bash
kubectl apply -f kubernetes/manifests/app/ingress.yaml
```

Check certificate status:
```bash
kubectl get certificate
kubectl describe certificate demo-crm-tls
```

## 6) Access the application
If you are using Ingress, use the Ingress hostname once DNS is set:
```bash
kubectl get ingress demo-crm
```

If the Service is still a LoadBalancer, use the external IP:
```bash
kubectl get svc demo-crm
```

## 7) Quick troubleshooting commands

### App not starting / CrashLoopBackOff
```bash
kubectl describe pod -l app=demo-crm
kubectl logs -l app=demo-crm --tail=200
```

### Mongo connectivity issues
```bash
kubectl get pods | rg demo-mongo
kubectl logs <mongo-pod> --tail=200
kubectl describe pod <mongo-pod>
```

### Verify config injected
```bash
kubectl exec -it deploy/demo-crm -- printenv | egrep 'MONGODB_URI|PERSISTENCE|LOG_LEVEL'
```

## 8) Cleanup (optional)

Remove app resources:
```bash
kubectl delete -f kubernetes/manifests/app/ingress.yaml
kubectl delete -f kubernetes/manifests/app/service.yaml
kubectl delete -f kubernetes/manifests/app/deployment.yaml
kubectl delete -f kubernetes/manifests/app/configmap.yaml
kubectl delete -f kubernetes/manifests/app/clusterissuer.yaml
```

Remove MongoDB Helm release:
```bash
helm uninstall demo-mongo
```

Remove MongoDB auth Secret:
```bash
kubectl delete secret demo-mongo-auth
```

Remove Ingress controller (if installed):
```bash
helm uninstall nginx-ingress -n nginx-ingress
```

Remove cert-manager (if installed):
```bash
helm uninstall cert-manager -n cert-manager
```

Remove app Secret:
```bash
kubectl delete secret demo-crm-mongodb-uri
```
