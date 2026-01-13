#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MONGODB_RELEASE_NAME="${MONGODB_RELEASE_NAME:-demo-mongo}"

APP_MANIFESTS=(
  "kubernetes/manifests/app/service.yaml"
  "kubernetes/manifests/app/deployment.yaml"
  "kubernetes/manifests/app/configmap.yaml"
  "kubernetes/manifests/app/ingress.yaml"
  "kubernetes/manifests/app/clusterissuer.yaml"
)

APP_SECRETS=(
  "demo-crm-mongodb-uri"
  "demo-mongo-auth"
)

log() {
  printf '%s\n' "$*"
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "$1 is required but not found in PATH."
  fi
}

require_kube_context() {
  if ! kubectl config current-context >/dev/null 2>&1; then
    die "kubectl context is not set. Run 'kubectl config use-context'."
  fi
}

delete_app_manifests() {
  local manifest
  for manifest in "${APP_MANIFESTS[@]}"; do
    kubectl delete -f "${ROOT_DIR}/${manifest}" --ignore-not-found
  done
}

uninstall_cert_manager() {
  helm uninstall cert-manager -n cert-manager --ignore-not-found
  kubectl delete namespace cert-manager --ignore-not-found
}

uninstall_mongodb() {
  helm uninstall "${MONGODB_RELEASE_NAME}" --ignore-not-found
  kubectl delete statefulset \
    -l "app.kubernetes.io/instance=${MONGODB_RELEASE_NAME}" \
    -l "app.kubernetes.io/name=mongodb" \
    --ignore-not-found --wait=false
  kubectl delete secret "${APP_SECRETS[@]}" --ignore-not-found
  kubectl delete pvc -l "app.kubernetes.io/instance=${MONGODB_RELEASE_NAME}" --ignore-not-found --wait=false
}

main() {
  require_command kubectl
  require_command helm
  require_kube_context
  log "Using kube context: $(kubectl config current-context)"

  delete_app_manifests
  uninstall_cert_manager
  uninstall_mongodb

  log "Done."
}

main "$@"
