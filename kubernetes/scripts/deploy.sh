#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RUN_INIT_JOB="${RUN_INIT_JOB:-1}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300s}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH." >&2
  exit 1
fi

if [ ! -f "${ROOT_DIR}/creds/mongo-keyfile" ]; then
  echo "Missing creds/mongo-keyfile. Create it before running this script." >&2
  exit 1
fi

if [ ! -f "${ROOT_DIR}/creds/mongo.env" ]; then
  echo "Missing creds/mongo.env. Create or edit it before running this script." >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
. "${ROOT_DIR}/creds/mongo.env"
set +a

: "${MONGO_ROOT_USER:?Missing MONGO_ROOT_USER in creds/mongo.env}"
: "${MONGO_ROOT_PASS:?Missing MONGO_ROOT_PASS in creds/mongo.env}"
: "${MONGO_APP_USER:?Missing MONGO_APP_USER in creds/mongo.env}"
: "${MONGO_APP_PASS:?Missing MONGO_APP_PASS in creds/mongo.env}"
: "${MONGODB_URI:?Missing MONGODB_URI in creds/mongo.env}"

echo "Using kube context: $(kubectl config current-context)"

kubectl create secret generic mongo-keyfile \
  --from-file=keyfile="${ROOT_DIR}/creds/mongo-keyfile" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic mongo-credentials \
  --from-literal=root-username="${MONGO_ROOT_USER}" \
  --from-literal=root-password="${MONGO_ROOT_PASS}" \
  --from-literal=app-username="${MONGO_APP_USER}" \
  --from-literal=app-password="${MONGO_APP_PASS}" \
  --from-literal=MONGODB_URI="${MONGODB_URI}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${ROOT_DIR}/kubernetes/manifests/mongodb/service.yaml"
kubectl apply -f "${ROOT_DIR}/kubernetes/manifests/mongodb/statefulset.yaml"
kubectl rollout status statefulset/mongodb

if [ "${RUN_INIT_JOB}" = "1" ]; then
  kubectl apply -f "${ROOT_DIR}/kubernetes/manifests/mongodb/init-job.yaml"
  kubectl wait --for=condition=complete job/mongodb-init --timeout="${WAIT_TIMEOUT}"
  kubectl logs job/mongodb-init
fi

kubectl apply -f "${ROOT_DIR}/kubernetes/manifests/app/configmap.yaml"
kubectl apply -f "${ROOT_DIR}/kubernetes/manifests/app/deployment.yaml"
kubectl apply -f "${ROOT_DIR}/kubernetes/manifests/app/service.yaml"
kubectl rollout status deployment/demo-crm

kubectl get svc demo-crm

echo "Done. Open http://<EXTERNAL-IP>/ when it appears."
