#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DELETE_SECRETS="${DELETE_SECRETS:-0}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH." >&2
  exit 1
fi

echo "Using kube context: $(kubectl config current-context)"

kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/app/service.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/app/deployment.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/app/configmap.yaml" --ignore-not-found

kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/mongodb/init-job.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/mongodb/statefulset.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/kubernetes/manifests/mongodb/service.yaml" --ignore-not-found

if [ "${DELETE_SECRETS}" = "1" ]; then
  kubectl delete secret mongo-credentials mongo-keyfile --ignore-not-found
fi

echo "Done."
