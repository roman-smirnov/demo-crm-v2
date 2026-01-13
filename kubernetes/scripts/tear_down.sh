#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MONGODB_RELEASE_NAME="${MONGODB_RELEASE_NAME:-demo-mongo}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH." >&2
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required but not found in PATH." >&2
  exit 1
fi

echo "Using kube context: $(kubectl config current-context)"

kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/app/service.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/app/deployment.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/app/configmap.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/app/ingress.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/app/clusterissuer.yaml" --ignore-not-found
helm uninstall cert-manager -n cert-manager --ignore-not-found

kubectl delete namespace cert-manager --ignore-not-found

helm uninstall "${MONGODB_RELEASE_NAME}" --ignore-not-found

kubectl delete statefulset \
  -l "app.kubernetes.io/instance=${MONGODB_RELEASE_NAME}" \
  -l "app.kubernetes.io/name=mongodb" \
  --ignore-not-found --wait=false
kubectl delete secret demo-crm-mongodb-uri demo-mongo-auth --ignore-not-found
kubectl delete pvc -l "app.kubernetes.io/instance=${MONGODB_RELEASE_NAME}" --ignore-not-found --wait=false

echo "Done."
