# Kubernetes Deployment (demo-crm)

This repo deploys:
- `demo-crm` (Next.js app) via the Helm chart in `kubernetes/helm/demo-crm`
- MongoDB via the `bitnami/mongodb` Helm chart (standalone by default, or as a chart dependency)
- Optional dependency charts: cert-manager and NGINX Ingress Controller (F5), disabled by default
- Ingress + cert-manager for TLS (optional, wired into the chart and `deploy.sh`)

Paths:
- `kubernetes/helm/demo-crm/`: app Helm chart + values
- `kubernetes/helm/`: MongoDB Helm values overrides
- `kubernetes/scripts/`: deploy and teardown helpers
- `creds/`: .env files used to create Secrets

## Prerequisites
- A running Kubernetes cluster
- `kubectl` configured to talk to the cluster
- `helm` installed
- An ingress controller with an `ingressClassName` of `nginx` if you plan to use Ingress
- `deploy.sh` runs `helm dependency build` automatically. For manual installs with dependencies
  enabled, run `helm dependency build kubernetes/helm/demo-crm` or add `--dependency-update`.
- Update these before you deploy:
  - `kubernetes/helm/demo-crm/values.yaml` (ingress host/TLS + clusterIssuer email)
  - Optional: create `kubernetes/helm/demo-crm/values_override.yaml` for local overrides

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
- `demo-crm-mongodb-uri` in `${APP_NAMESPACE}` (used by the app chart)

## Quick start (script)
1. Update `kubernetes/helm/demo-crm/values.yaml` (or create `kubernetes/helm/demo-crm/values_override.yaml`).
2. Fill `creds/mongodb_auth.env` and `creds/mongo.env`.
3. Ensure an ingress controller exists (unless you enable `nginxIngress.enabled` in the chart).
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
APP_RELEASE_NAME=demo-crm \
APP_RESOURCE_NAME=demo-crm \
APP_CHART_PATH=kubernetes/helm/demo-crm \
APP_VALUES_FILE= \
APP_VALUES_OVERRIDE_FILE=kubernetes/helm/demo-crm/values_override.yaml \
MONGODB_NAMESPACE=default \
MONGODB_RELEASE_NAME=demo-mongo \
MONGODB_CHART=bitnami/mongodb \
./kubernetes/scripts/deploy.sh
```

### What `deploy.sh` does
- Validates `kubectl` and `helm` and checks required files
- Creates namespaces if missing
- Builds app chart dependencies with `helm dependency build`
- Creates Secrets from `.env` files
- Installs/upgrades MongoDB with Helm using `kubernetes/helm/mongodb_values_override.yaml`
  (and `kubernetes/helm/mongodb_values.yaml` if present)
- Installs/upgrades the app Helm chart in `kubernetes/helm/demo-crm`
- Waits for an Ingress address and pauses until DNS is updated
- Installs cert-manager if missing and re-runs the app chart to create the ClusterIssuer
- Prints rollout and service/ingress status

## Tear down (script)
```bash
./kubernetes/scripts/tear_down.sh
```

Notes:
- Uninstalls the app Helm release, cert-manager release + namespace, MongoDB Helm release,
  MongoDB StatefulSet/PVCs, and both Secrets.
- Set `APP_NAMESPACE` and `MONGODB_NAMESPACE` if you deployed outside the defaults.

## Manual steps (optional)
### 1) Install MongoDB with Helm
Skip this step if you set `mongodb.enabled=true` in the app chart.

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
If you enable chart dependencies (`mongodb.enabled`, `certManager.enabled`, `nginxIngress.enabled`)
or the `charts/` directory is empty, run `helm dependency build kubernetes/helm/demo-crm`
or add `--dependency-update` to the install command.

```bash
helm upgrade --install demo-crm kubernetes/helm/demo-crm \
  -n <app-namespace> \
  --create-namespace \
  --set appMongo.uri.secretName=demo-crm-mongodb-uri
```

Wait for the Deployment:
```bash
kubectl rollout status deployment/demo-crm -n <app-namespace>
kubectl get pods -l app=demo-crm -n <app-namespace> -o wide
```

### 4) cert-manager / TLS
If you are not using the script, install cert-manager and enable the ClusterIssuer.
Skip the install step if you set `certManager.enabled=true` in the app chart.
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl create namespace cert-manager

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true

kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
helm upgrade --install demo-crm kubernetes/helm/demo-crm \
  -n <app-namespace> \
  --set clusterIssuer.enabled=true
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
