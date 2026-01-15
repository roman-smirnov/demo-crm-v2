#!/usr/bin/env bash
set -euo pipefail

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_RELEASE_NAME="${ARGOCD_RELEASE_NAME:-argo-cd}"
ARGOCD_CHART="${ARGOCD_CHART:-argo/argo-cd}"
ARGOCD_VALUES_FILE="${ARGOCD_VALUES_FILE:-kubernetes/helm/argocd_values.yaml}"
ARGOCD_VALUES_OVERRIDE_FILE="${ARGOCD_VALUES_OVERRIDE_FILE:-}"
ARGOCD_ADMIN_PASSWORD_FILE="${ARGOCD_ADMIN_PASSWORD_FILE:-creds/argocd.env}"

ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-}"
ARGOCD_ADMIN_PASSWORD_HASH="${ARGOCD_ADMIN_PASSWORD_HASH:-}"

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

load_admin_password_file() {
  if [ ! -f "${ARGOCD_ADMIN_PASSWORD_FILE}" ]; then
    return
  fi

  while IFS='=' read -r key value; do
    case "${key}" in
      "" | \#*) continue ;;
    esac

    case "${key}" in
      ARGOCD_ADMIN_PASSWORD|ARGOCD_ADMIN_PASSWORD_HASH)
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        printf -v "${key}" '%s' "${value}"
        ;;
    esac
  done < "${ARGOCD_ADMIN_PASSWORD_FILE}"
}

generate_bcrypt_hash() {
  local password="$1"

  if ! command -v htpasswd >/dev/null 2>&1; then
    die "htpasswd is required to hash ARGOCD_ADMIN_PASSWORD. Install it or set ARGOCD_ADMIN_PASSWORD_HASH."
  fi

  htpasswd -nbBC 10 "" "${password}" | cut -d: -f2 | tr -d '\n'
}

resolve_admin_password_hash() {
  if [ -n "${ARGOCD_ADMIN_PASSWORD_HASH}" ]; then
    printf '%s' "${ARGOCD_ADMIN_PASSWORD_HASH}"
    return
  fi

  if [ -z "${ARGOCD_ADMIN_PASSWORD}" ]; then
    die "Set ARGOCD_ADMIN_PASSWORD or ARGOCD_ADMIN_PASSWORD_HASH before running this script."
  fi

  generate_bcrypt_hash "${ARGOCD_ADMIN_PASSWORD}"
}

install_argocd() {
  local -a values_args=()
  local admin_hash
  local admin_mtime

  if [ ! -f "${ARGOCD_VALUES_FILE}" ]; then
    die "Missing values file: ${ARGOCD_VALUES_FILE}"
  fi
  values_args+=(-f "${ARGOCD_VALUES_FILE}")

  if [ -n "${ARGOCD_VALUES_OVERRIDE_FILE}" ]; then
    if [ ! -f "${ARGOCD_VALUES_OVERRIDE_FILE}" ]; then
      die "Missing override values file: ${ARGOCD_VALUES_OVERRIDE_FILE}"
    fi
    values_args+=(-f "${ARGOCD_VALUES_OVERRIDE_FILE}")
  fi

  admin_hash="$(resolve_admin_password_hash)"
  admin_mtime="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  helm repo add argo https://argoproj.github.io/argo-helm --force-update
  helm repo update argo

  helm upgrade --install "${ARGOCD_RELEASE_NAME}" "${ARGOCD_CHART}" \
    -n "${ARGOCD_NAMESPACE}" \
    --create-namespace \
    "${values_args[@]}" \
    --set-string "configs.secret.argocdServerAdminPassword=${admin_hash}" \
    --set-string "configs.secret.argocdServerAdminPasswordMtime=${admin_mtime}"
}

main() {
  require_command kubectl
  require_command helm
  require_kube_context
  require_cluster_access
  log "Using kube context: $(kubectl config current-context)"

  load_admin_password_file
  install_argocd

  log "Argo CD installed. Ingresses:"
  kubectl get ingress -n "${ARGOCD_NAMESPACE}"
}

main "$@"
