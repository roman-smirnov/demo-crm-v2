#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CERT_MANAGER_RELEASE_NAME="${CERT_MANAGER_RELEASE_NAME:-cert-manager}"
CERT_MANAGER_CHART="${CERT_MANAGER_CHART:-jetstack/cert-manager}"
CERT_MANAGER_VALUES_FILE="${CERT_MANAGER_VALUES_FILE:-}"
CLUSTER_ISSUER_FILE="${CLUSTER_ISSUER_FILE:-kubernetes/gitops/cert-manager/clusterissuer.yaml}"

ARGOCD_APP_FILE="${ARGOCD_APP_FILE:-kubernetes/gitops/argocd/demo-crm-app.yaml}"
ARGOCD_REPO_URL="${ARGOCD_REPO_URL:-https://github.com/roman-smirnov/demo-crm-app}"
ARGOCD_REPO_USERNAME="${ARGOCD_REPO_USERNAME:-}"
ARGOCD_REPO_PASSWORD="${ARGOCD_REPO_PASSWORD:-}"
ARGOCD_REPO_SECRET_NAME="${ARGOCD_REPO_SECRET_NAME:-demo-crm-app-repo}"

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

require_cluster_access() {
  if ! kubectl get ns >/dev/null 2>&1; then
    die "Unable to reach the cluster with kubectl."
  fi
}

install_cert_manager() {
  local -a values_args=()

  if [ -n "${CERT_MANAGER_VALUES_FILE}" ]; then
    if [ ! -f "${CERT_MANAGER_VALUES_FILE}" ]; then
      die "Missing cert-manager values file: ${CERT_MANAGER_VALUES_FILE}"
    fi
    values_args+=( -f "${CERT_MANAGER_VALUES_FILE}" )
  fi

  helm repo add jetstack https://charts.jetstack.io --force-update
  helm repo update jetstack

  helm upgrade --install "${CERT_MANAGER_RELEASE_NAME}" "${CERT_MANAGER_CHART}" \
    -n "${CERT_MANAGER_NAMESPACE}" \
    --create-namespace \
    --set installCRDs=true \
    "${values_args[@]+"${values_args[@]}"}"
}

apply_cluster_issuer() {
  if [ ! -f "${CLUSTER_ISSUER_FILE}" ]; then
    die "Missing ClusterIssuer manifest: ${CLUSTER_ISSUER_FILE}"
  fi

  kubectl apply -f "${CLUSTER_ISSUER_FILE}"
}

install_argocd() {
  ("${ROOT_DIR}/kubernetes/scripts/install_argocd.sh")
}

configure_repo_access() {
  if [ -z "${ARGOCD_REPO_USERNAME}" ] || [ -z "${ARGOCD_REPO_PASSWORD}" ]; then
    die "Set ARGOCD_REPO_USERNAME and ARGOCD_REPO_PASSWORD to access the private repo."
  fi

  kubectl apply -n "${ARGOCD_NAMESPACE}" -f - <<EOT
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGOCD_REPO_SECRET_NAME}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  url: ${ARGOCD_REPO_URL}
  username: ${ARGOCD_REPO_USERNAME}
  password: ${ARGOCD_REPO_PASSWORD}
EOT
}

apply_application() {
  if [ ! -f "${ARGOCD_APP_FILE}" ]; then
    die "Missing Application manifest: ${ARGOCD_APP_FILE}"
  fi

  kubectl apply -f "${ARGOCD_APP_FILE}"
}

main() {
  require_command kubectl
  require_command helm
  require_kube_context
  require_cluster_access

  log "Using kube context: $(kubectl config current-context)"

  install_cert_manager
  apply_cluster_issuer
  install_argocd
  configure_repo_access
  apply_application

  log "GitOps bootstrap complete."
  kubectl get applications.argoproj.io -n "${ARGOCD_NAMESPACE}"
}

main "$@"
