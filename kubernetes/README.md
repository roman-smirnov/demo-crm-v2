# Kubernetes Deployment (demo-crm)

This repo deploys:
- `demo-crm` (Next.js app) as a Deployment + Service (ClusterIP)
- MongoDB via the `bitnami/mongodb` Helm chart (replicaset)
- Ingress + cert-manager for TLS (optional but wired into the manifests and `deploy.sh`)

Paths:
- `kubernetes/manifests/app/`: app manifests + ClusterIssuer
- `kubernetes/helm/`: MongoDB Helm values overrides
- `kubernetes/scripts/`: deploy and teardown helpers
- `creds/`: .env files used to create Secrets

## Prerequisites
- A running Kubernetes cluster
- `kubectl` configured to talk to the cluster
- `helm` installed
- An ingress controller with an `ingressClassName` of `nginx` if you plan to use Ingress
- Update these before you deploy:
  - `kubernetes/manifests/app/ingress.yaml` (host + TLS secret name)
  - `kubernetes/manifests/app/clusterissuer.yaml` (email)

Verify access:
```bash
kubectl get nodes
```

## Secrets (.env files)
`deploy.sh` creates Kubernetes Secrets from local `.env` files:

`creds/mongodb_auth.env` (Bitnami MongoDB auth keys):
```bash
mongodb-root-password=change-me-root
mongodb-passwords=change-me-app
mongodb-replica-set-key=change-me-repl
```

`creds/mongo.env` (app connection string):
```bash
MONGODB_URI=mongodb://<user>:<pass>@<host1>,<host2>/demo_crm?authSource=demo_crm&replicaSet=rs0
```

Secrets created:
- `demo-mongo-auth` in `${MONGODB_NAMESPACE}` (used by the Helm chart)
- `demo-crm-mongodb-uri` in `${APP_NAMESPACE}` (used by the app Deployment)

## Quick start (script)
1. Update `kubernetes/manifests/app/ingress.yaml` and `kubernetes/manifests/app/clusterissuer.yaml`.
2. Fill `creds/mongodb_auth.env` and `creds/mongo.env`.
3. Ensure an ingress controller exists (if you are using Ingress).
4. Run:
```bash
./kubernetes/scripts/deploy.sh
```

For non-interactive runs (skip DNS prompt):
```bash
DNS_CONFIRM=y ./kubernetes/scripts/deploy.sh
```

Optional overrides (defaults shown):
```bash
APP_NAMESPACE=default \
MONGODB_NAMESPACE=default \
MONGODB_RELEASE_NAME=demo-mongo \
MONGODB_CHART=bitnami/mongodb \
./kubernetes/scripts/deploy.sh
```

### What `deploy.sh` does
- Validates `kubectl` and `helm` and checks required files
- Creates namespaces if missing
- Creates Secrets from `.env` files
- Installs/upgrades MongoDB with Helm using `kubernetes/helm/mongodb_values_override.yaml`
  (and `kubernetes/helm/mongodb_values.yaml` if present)
- Applies app ConfigMap, Deployment, Service, and Ingress
- Waits for an Ingress address and pauses until DNS is updated
- Installs cert-manager if missing, applies the ClusterIssuer, and re-applies Ingress
- Prints rollout and service/ingress status

## Tear down (script)
```bash
./kubernetes/scripts/tear_down.sh
```

Notes:
- Deletes app manifests, cert-manager release + namespace, MongoDB Helm release,
  MongoDB StatefulSet/PVCs, and both Secrets.
- App resources are deleted in the current kubectl namespace. If you deployed to
  a custom namespace, set your context namespace first or delete manually.

## Manual steps (optional)
### 1) Install MongoDB with Helm
Create the Secret from the `.env` file:
```bash
kubectl create secret generic demo-mongo-auth \
  --from-env-file=creds/mongodb_auth.env \
  --dry-run=client -o yaml | kubectl apply -n <mongodb-namespace> -f -
```

Install or upgrade the chart:
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install demo-mongo bitnami/mongodb \
  -n <mongodb-namespace> \
  --create-namespace \
  -f kubernetes/helm/mongodb_values_override.yaml
```

Optionally add `-f kubernetes/helm/mongodb_values.yaml` if you create it.

### 2) Create the MONGODB_URI Secret
```bash
kubectl create secret generic demo-crm-mongodb-uri \
  --from-env-file=creds/mongo.env \
  --dry-run=client -o yaml | kubectl apply -n <app-namespace> -f -
```

### 3) Deploy the app
```bash
kubectl apply -n <app-namespace> -f kubernetes/manifests/app/configmap.yaml
kubectl apply -n <app-namespace> -f kubernetes/manifests/app/deployment.yaml
kubectl apply -n <app-namespace> -f kubernetes/manifests/app/service.yaml
kubectl apply -n <app-namespace> -f kubernetes/manifests/app/ingress.yaml
```

Wait for the Deployment:
```bash
kubectl rollout status deployment/demo-crm -n <app-namespace>
kubectl get pods -l app=demo-crm -n <app-namespace> -o wide
```

### 4) cert-manager / TLS
If you are not using the script, install cert-manager and apply the ClusterIssuer:
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true

kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
kubectl apply -f kubernetes/manifests/app/clusterissuer.yaml
kubectl apply -n <app-namespace> -f kubernetes/manifests/app/ingress.yaml
```

### 5) Access the application
If you are using Ingress, use the Ingress hostname once DNS is set:
```bash
kubectl get ingress demo-crm -n <app-namespace>
```

If you expose the Service another way, inspect it directly:
```bash
kubectl get svc demo-crm -n <app-namespace>
```

## Load testing (resources)
Run a simple in-cluster load test against the Service:
```bash
APP_NAMESPACE=default \
DURATION=2m \
CONCURRENCY=50 \
./kubernetes/scripts/load_test.sh
```

Override the target URL if you want to hit Ingress instead:
```bash
TARGET_URL=https://your-hostname.example.com/ \
./kubernetes/scripts/load_test.sh
```

Watch resource usage (requires metrics-server):
```bash
kubectl top pods -n <app-namespace>
```

## Troubleshooting
App not starting / CrashLoopBackOff:
```bash
kubectl describe pod -l app=demo-crm -n <app-namespace>
kubectl logs -l app=demo-crm -n <app-namespace> --tail=200
```

Mongo connectivity issues:
```bash
kubectl get pods -n <mongodb-namespace> | rg demo-mongo
kubectl logs <mongo-pod> -n <mongodb-namespace> --tail=200
kubectl describe pod <mongo-pod> -n <mongodb-namespace>
```

Verify config injected:
```bash
kubectl exec -it deploy/demo-crm -n <app-namespace> -- printenv | egrep 'MONGODB_URI|PERSISTENCE|LOG_LEVEL'
```
