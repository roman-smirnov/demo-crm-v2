#!/usr/bin/env bash
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-app}"
APP_RELEASE_NAME="${APP_RELEASE_NAME:-demo-crm}"
MONGODB_NAMESPACE="${MONGODB_NAMESPACE:-mongo}"
MONGODB_RELEASE_NAME="${MONGODB_RELEASE_NAME:-demo-mongo}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert}"

MONGODB_AUTH_SECRET_NAME="${MONGODB_AUTH_SECRET_NAME:-demo-mongo-auth}"
MONGODB_URI_SECRET_NAME="${MONGODB_URI_SECRET_NAME:-demo-crm-mongodb-uri}"

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

uninstall_app_chart() {
  helm uninstall "${APP_RELEASE_NAME}" -n "${APP_NAMESPACE}" --ignore-not-found
  kubectl delete secret "${MONGODB_URI_SECRET_NAME}" -n "${APP_NAMESPACE}" --ignore-not-found
}

uninstall_cert_manager() {
  helm uninstall cert-manager -n "${CERT_MANAGER_NAMESPACE}" --ignore-not-found
  kubectl delete namespace "${CERT_MANAGER_NAMESPACE}" --ignore-not-found
}

uninstall_mongodb() {
  helm uninstall "${MONGODB_RELEASE_NAME}" -n "${MONGODB_NAMESPACE}" --ignore-not-found
  kubectl delete statefulset \
    -l "app.kubernetes.io/instance=${MONGODB_RELEASE_NAME}" \
    -l "app.kubernetes.io/name=mongodb" \
    -n "${MONGODB_NAMESPACE}" \
    --ignore-not-found --wait=false
  kubectl delete secret "${MONGODB_AUTH_SECRET_NAME}" -n "${MONGODB_NAMESPACE}" --ignore-not-found
  kubectl delete pvc -l "app.kubernetes.io/instance=${MONGODB_RELEASE_NAME}" -n "${MONGODB_NAMESPACE}" --ignore-not-found --wait=false
}

main() {
  require_command kubectl
  require_command helm
  require_kube_context
  log "Using kube context: $(kubectl config current-context)"

  uninstall_app_chart
  uninstall_cert_manager
  uninstall_mongodb

  log "Done."
}

main "$@"
