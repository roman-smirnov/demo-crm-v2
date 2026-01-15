#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CERT_MANAGER_RELEASE_NAME="${CERT_MANAGER_RELEASE_NAME:-cert-manager}"
ARGOCD_APP_FILE="${ARGOCD_APP_FILE:-kubernetes/gitops/argocd/demo-crm-app.yaml}"
CLUSTER_ISSUER_FILE="${CLUSTER_ISSUER_FILE:-kubernetes/gitops/cert-manager/clusterissuer.yaml}"
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

remove_application() {
  if [ -f "${ARGOCD_APP_FILE}" ]; then
    kubectl delete -f "${ARGOCD_APP_FILE}" --ignore-not-found
  fi
}

remove_repo_access() {
  kubectl delete secret "${ARGOCD_REPO_SECRET_NAME}" -n "${ARGOCD_NAMESPACE}" --ignore-not-found
}

remove_argocd() {
  if [ -x "kubernetes/scripts/tear_down_argocd.sh" ]; then
    kubernetes/scripts/tear_down_argocd.sh
  fi
}

remove_cluster_issuer() {
  if [ -f "${CLUSTER_ISSUER_FILE}" ]; then
    kubectl delete -f "${CLUSTER_ISSUER_FILE}" --ignore-not-found
  fi
}

remove_cert_manager() {
  if command -v helm >/dev/null 2>&1; then
    helm uninstall "${CERT_MANAGER_RELEASE_NAME}" -n "${CERT_MANAGER_NAMESPACE}" >/dev/null 2>&1 || true
  fi
  kubectl delete namespace "${CERT_MANAGER_NAMESPACE}" --ignore-not-found
}

main() {
  require_command kubectl
  require_kube_context
  require_cluster_access

  log "Using kube context: $(kubectl config current-context)"

  remove_application
  remove_repo_access
  remove_argocd
  remove_cluster_issuer
  remove_cert_manager

  log "GitOps teardown complete."
}

main "$@"
