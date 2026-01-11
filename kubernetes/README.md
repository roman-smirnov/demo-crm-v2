# Kubernetes App Deployment Instructions

This repo deploys:
- `demo-crm` (Next.js app) as a Deployment + LoadBalancer Service
- MongoDB as a StatefulSet (required by the current app Deployment, because it expects `MONGODB_URI` from a Secret)

All manifests are under `./kubernetes/manifests/`. Helper scripts live under `./kubernetes/scripts/`.

## Prerequisites
- A running Kubernetes cluster (GKE or any other)
- `kubectl` configured to talk to the cluster
- (GKE only) `gcloud` if you use the helper scripts

Verify access:
```bash
kubectl get nodes
```

## Quick start (script)
If you prefer a single command, use the deployment script. It expects:
- `creds/mongo-keyfile` (replica set keyfile)
- `creds/mongo.env` (local env file with `MONGO_*` values and `MONGODB_URI`)

Run from the repo root:
```bash
./kubernetes/scripts/deploy.sh
```

Optional flags:
```bash
RUN_INIT_JOB=0 ./kubernetes/scripts/deploy.sh
WAIT_TIMEOUT=600s ./kubernetes/scripts/deploy.sh
```

If you want to run the steps manually, follow the sections below.

## Tear down (script)
Remove the app and MongoDB resources:
```bash
./kubernetes/scripts/tear_down.sh
```

Remove Secrets too:
```bash
DELETE_SECRETS=1 ./kubernetes/scripts/tear_down.sh
```

## 1) Create required Secrets (MongoDB + app connection)
The app Deployment reads `MONGODB_URI` from a Secret named `mongo-credentials`.
MongoDB also expects:
- `mongo-credentials` with `root-username` and `root-password`
- `mongo-keyfile` Secret (replica set keyfile)

From the repo root:

### 1.1 Create the Mongo keyfile Secret
```bash
kubectl create secret generic mongo-keyfile \
  --from-file=keyfile=./creds/mongo-keyfile
```

### 1.2 Option A: Use a local env file (recommended)
Create `creds/mongo.env` (example values):
```bash
MONGO_ROOT_USER=admin
MONGO_ROOT_PASS=change-me
MONGO_APP_USER=demo_crm
MONGO_APP_PASS=change-me
MONGODB_URI="mongodb://demo_crm:change-me@mongodb-0.mongodb:27017,mongodb-1.mongodb:27017/demo-crm?authSource=demo-crm&replicaSet=rs0"
```

Then create the Secret from it:
```bash
set -a
. creds/mongo.env
set +a

kubectl create secret generic mongo-credentials \
  --from-literal=root-username="$MONGO_ROOT_USER" \
  --from-literal=root-password="$MONGO_ROOT_PASS" \
  --from-literal=app-username="$MONGO_APP_USER" \
  --from-literal=app-password="$MONGO_APP_PASS" \
  --from-literal=MONGODB_URI="$MONGODB_URI" \
  --dry-run=client -o yaml | kubectl apply -f -
```
If you use this, you can skip 1.3 and 1.4.

### 1.3 Option B: Create MongoDB credentials Secret
Choose a root username/password and create the Secret:
```bash
export MONGO_ROOT_USER="root"
export MONGO_ROOT_PASS="change-me"

kubectl create secret generic mongo-credentials \
  --from-literal=root-username="$MONGO_ROOT_USER" \
  --from-literal=root-password="$MONGO_ROOT_PASS"
```

If you plan to run the init job, add app credentials as well:
```bash
kubectl patch secret mongo-credentials \
  -p='{"stringData":{"app-username":"demo_crm","app-password":"change-me"}}'
```

### 1.4 Add `MONGODB_URI` to the same Secret (required by the app)
After MongoDB is deployed, the pod DNS names will be stable. For this StatefulSet:
- `mongodb-0.mongodb`
- `mongodb-1.mongodb`

Create the URI and store it in the Secret (root user example):
```bash
export MONGODB_URI="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASS}@mongodb-0.mongodb:27017,mongodb-1.mongodb:27017/demo-crm?authSource=admin&replicaSet=rs0"

kubectl patch secret mongo-credentials \
  -p='{"stringData":{"MONGODB_URI":"'"$MONGODB_URI"'"}}'
```

If you are using the app user, swap the user/pass and set `authSource=demo-crm`.

Confirm the keys exist:
```bash
kubectl get secret mongo-credentials -o jsonpath='{.data}' && echo
```

## 2) Deploy MongoDB (StatefulSet)
Apply the MongoDB Service and StatefulSet:
```bash
kubectl apply -f kubernetes/manifests/mongodb/service.yaml
kubectl apply -f kubernetes/manifests/mongodb/statefulset.yaml
```

Wait for MongoDB to be ready:
```bash
kubectl rollout status statefulset/mongodb
kubectl get pods -l app=mongodb -o wide
```

### 2.1 Initialize replica set + app user (Job)
Apply the init Job (safe to re-run):
```bash
kubectl apply -f kubernetes/manifests/mongodb/init-job.yaml
kubectl wait --for=condition=complete job/mongodb-init --timeout=300s
kubectl logs job/mongodb-init
```

You can delete the Job after it completes:
```bash
kubectl delete -f kubernetes/manifests/mongodb/init-job.yaml
```

This requires `app-username` and `app-password` in the `mongo-credentials` Secret. If you are not creating an app user, skip this step and use root credentials in `MONGODB_URI`.


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

## 4) Access the application
Get the external IP created by the LoadBalancer Service:
```bash
kubectl get svc demo-crm
```

Open the `EXTERNAL-IP` in a browser (HTTP). Example:
- `http://<EXTERNAL-IP>/`

## 5) Quick troubleshooting commands

### App not starting / CrashLoopBackOff
```bash
kubectl describe pod -l app=demo-crm
kubectl logs -l app=demo-crm --tail=200
```

### Mongo connectivity issues
```bash
kubectl logs -l app=mongodb --tail=200
kubectl describe pod -l app=mongodb
```

### Verify config injected
```bash
kubectl exec -it deploy/demo-crm -- printenv | egrep 'MONGODB_URI|PERSISTENCE|LOG_LEVEL'
```

## 6) Cleanup (optional)

Remove app resources:
```bash
kubectl delete -f kubernetes/manifests/app/service.yaml
kubectl delete -f kubernetes/manifests/app/deployment.yaml
kubectl delete -f kubernetes/manifests/app/configmap.yaml
```

Remove Mongo resources:
```bash
kubectl delete -f kubernetes/manifests/mongodb/init-job.yaml
kubectl delete -f kubernetes/manifests/mongodb/statefulset.yaml
kubectl delete -f kubernetes/manifests/mongodb/service.yaml
```

Remove Secrets:
```bash
kubectl delete secret mongo-credentials mongo-keyfile
```
