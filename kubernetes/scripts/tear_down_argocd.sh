#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_RELEASE_NAME="${ARGOCD_RELEASE_NAME:-argo-cd}"

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

main() {
  require_command kubectl
  require_command helm
  require_kube_context
  log "Using kube context: $(kubectl config current-context)"

  helm uninstall "${ARGOCD_RELEASE_NAME}" -n "${ARGOCD_NAMESPACE}" --ignore-not-found
  kubectl delete namespace "${ARGOCD_NAMESPACE}" --ignore-not-found

  log "Done."
}

main "$@"
