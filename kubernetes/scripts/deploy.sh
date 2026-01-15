#!/usr/bin/env bash
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-app}"
MONGODB_RELEASE_NAME="${MONGODB_RELEASE_NAME:-demo-mongo}"
MONGODB_NAMESPACE="${MONGODB_NAMESPACE:-mongo}"
MONGODB_CHART="${MONGODB_CHART:-bitnami/mongodb}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert}"

APP_RELEASE_NAME="${APP_RELEASE_NAME:-demo-crm}"
APP_CHART_PATH="${APP_CHART_PATH:-kubernetes/helm/demo-crm}"
APP_VALUES_FILE="${APP_VALUES_FILE:-}"
APP_VALUES_OVERRIDE_FILE="${APP_VALUES_OVERRIDE_FILE:-kubernetes/helm/demo-crm/values_override.yaml}"
APP_DEPENDENCIES_BUILT="${APP_DEPENDENCIES_BUILT:-false}"
APP_RESOURCE_NAME="${APP_RESOURCE_NAME:-${APP_RELEASE_NAME}}"
APP_NAME="${APP_RESOURCE_NAME}"
INGRESS_NAME="${INGRESS_NAME:-${APP_RESOURCE_NAME}}"

MONGODB_VALUES_FILE="kubernetes/helm/mongodb_values.yaml"
MONGODB_VALUES_OVERRIDE_FILE="kubernetes/helm/mongodb_values_override.yaml"

MONGODB_AUTH_ENV_FILE="creds/mongodb_auth.env"
MONGODB_URI_ENV_FILE="creds/mongo.env"
MONGODB_AUTH_SECRET_NAME="demo-mongo-auth"
MONGODB_URI_SECRET_NAME="demo-crm-mongodb-uri"

REQUIRED_FILES=(
  "${MONGODB_AUTH_ENV_FILE}"
  "${MONGODB_URI_ENV_FILE}"
  "${APP_CHART_PATH}/Chart.yaml"
  "${APP_CHART_PATH}/values.yaml"
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

require_cluster_access() {
  if ! kubectl get ns >/dev/null 2>&1; then
    die "Unable to reach the cluster with kubectl."
  fi
}

helm_repo_update_with_retry() {
  local repo="$1"
  local max_attempts="${2:-3}"
  local delay_seconds="${3:-2}"
  local attempt=1

  while true; do
    if helm repo update "${repo}"; then
      return 0
    fi

    if [ "${attempt}" -ge "${max_attempts}" ]; then
      die "Failed to update Helm repo ${repo} after ${max_attempts} attempts."
    fi

    log "Helm repo update failed for ${repo}. Retrying in ${delay_seconds}s... (${attempt}/${max_attempts})"
    sleep "${delay_seconds}"
    attempt=$((attempt + 1))
    delay_seconds=$((delay_seconds * 2))
  done
}

helm_repo_update_all_with_retry() {
  local max_attempts="${1:-3}"
  local delay_seconds="${2:-2}"
  local attempt=1

  while true; do
    if helm repo update; then
      return 0
    fi

    if [ "${attempt}" -ge "${max_attempts}" ]; then
      die "Failed to update Helm repositories after ${max_attempts} attempts."
    fi

    log "Helm repo update failed. Retrying in ${delay_seconds}s... (${attempt}/${max_attempts})"
    sleep "${delay_seconds}"
    attempt=$((attempt + 1))
    delay_seconds=$((delay_seconds * 2))
  done
}

check_required_files() {
  local file
  for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${file}" ]; then
      die "Missing required file: ${file}"
    fi
  done
  if [ -n "${APP_VALUES_FILE}" ] && [ ! -f "${APP_VALUES_FILE}" ]; then
    die "Missing app values file: ${APP_VALUES_FILE}"
  fi
}

ensure_namespaces() {
  kubectl create namespace "${APP_NAMESPACE}" >/dev/null 2>&1 || true
  kubectl create namespace "${MONGODB_NAMESPACE}" >/dev/null 2>&1 || true
}

apply_secrets() {
  kubectl create secret generic "${MONGODB_AUTH_SECRET_NAME}" \
    --from-env-file="${MONGODB_AUTH_ENV_FILE}" \
    --dry-run=client -o yaml | kubectl apply -n "${MONGODB_NAMESPACE}" -f -
  kubectl create secret generic "${MONGODB_URI_SECRET_NAME}" \
    --from-env-file="${MONGODB_URI_ENV_FILE}" \
    --dry-run=client -o yaml | kubectl apply -n "${APP_NAMESPACE}" -f -
}

install_mongodb() {
  local -a values_args=()

  if [ -f "${MONGODB_VALUES_FILE}" ]; then
    values_args+=(-f "${MONGODB_VALUES_FILE}")
  fi
  if [ -f "${MONGODB_VALUES_OVERRIDE_FILE}" ]; then
    values_args+=(-f "${MONGODB_VALUES_OVERRIDE_FILE}")
  fi

  helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
  helm_repo_update_with_retry bitnami 3 2
  helm upgrade --install "${MONGODB_RELEASE_NAME}" "${MONGODB_CHART}" \
    -n "${MONGODB_NAMESPACE}" \
    --create-namespace \
    "${values_args[@]+"${values_args[@]}"}"
}

build_app_dependencies() {
  if [ "${APP_DEPENDENCIES_BUILT}" = "true" ]; then
    return
  fi

  helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm repo add nginx-stable https://helm.nginx.com/stable --force-update
  helm repo add bitnami-labs https://bitnami-labs.github.io/sealed-secrets --force-update

  helm_repo_update_all_with_retry 3 2

  helm dependency build "${APP_CHART_PATH}"
  APP_DEPENDENCIES_BUILT="true"
}

install_app_chart() {
  local -a values_args=()
  local -a set_args=()

  build_app_dependencies

  if [ -n "${APP_VALUES_FILE}" ] && [ -f "${APP_VALUES_FILE}" ]; then
    values_args+=(-f "${APP_VALUES_FILE}")
  fi
  if [ -f "${APP_VALUES_OVERRIDE_FILE}" ]; then
    values_args+=(-f "${APP_VALUES_OVERRIDE_FILE}")
  fi

  if [ -n "${APP_RESOURCE_NAME}" ]; then
    set_args+=(--set-string "fullnameOverride=${APP_RESOURCE_NAME}")
  fi
  set_args+=(--set-string "appMongo.uri.secretName=${MONGODB_URI_SECRET_NAME}")

  helm upgrade --install "${APP_RELEASE_NAME}" "${APP_CHART_PATH}" \
    -n "${APP_NAMESPACE}" \
    --create-namespace \
    "${values_args[@]+"${values_args[@]}"}" \
    "${set_args[@]+"${set_args[@]}"}" \
    "$@"
}

wait_for_ingress_address() {
  local address=""

  log "Waiting for Ingress external address..."
  while [ -z "${address}" ]; do
    address="$(kubectl get ingress "${INGRESS_NAME}" -n "${APP_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [ -z "${address}" ]; then
      address="$(kubectl get ingress "${INGRESS_NAME}" -n "${APP_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    fi
    if [ -z "${address}" ]; then
      log "Ingress address not ready yet. Retrying in 5s..."
      sleep 5
    fi
  done

  printf '%s\n' "${address}"
}

get_ingress_host() {
  kubectl get ingress "${INGRESS_NAME}" -n "${APP_NAMESPACE}" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true
}

confirm_dns() {
  local ingress_address="$1"
  local confirm="${DNS_CONFIRM:-}"

  if [ -z "${confirm}" ]; then
    if [ -t 0 ]; then
      read -r -p "Has the DNS A record been updated to point to ${ingress_address}? (y/N) " confirm
    elif [ -r /dev/tty ]; then
      read -r -p "Has the DNS A record been updated to point to ${ingress_address}? (y/N) " confirm </dev/tty
    else
      die "No interactive TTY available. Set DNS_CONFIRM=y to continue."
    fi
  fi

  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    die "Aborting. Update DNS and re-run."
  fi
}

ensure_cert_manager() {
  local dep_deployment="${APP_RELEASE_NAME}-cert-manager"

  if kubectl get deployment "${dep_deployment}" -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
    log "cert-manager already installed via chart dependency; skipping external install."
    return
  fi

  if ! kubectl get deployment cert-manager -n "${CERT_MANAGER_NAMESPACE}" >/dev/null 2>&1; then
    kubectl create namespace "${CERT_MANAGER_NAMESPACE}" >/dev/null 2>&1 || true
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm_repo_update_with_retry jetstack 3 2

    local -a install_args=(--namespace "${CERT_MANAGER_NAMESPACE}")
    if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
      install_args+=(--set installCRDs=false --set crds.enabled=false)
    else
      install_args+=(--set installCRDs=true)
    fi

    helm upgrade --install cert-manager jetstack/cert-manager "${install_args[@]}"
    kubectl wait --for=condition=Available deployment/cert-manager -n "${CERT_MANAGER_NAMESPACE}" --timeout=120s
  fi
}

final_status() {
  sleep 10
  kubectl rollout status deployment/"${APP_NAME}" -n "${APP_NAMESPACE}"
  kubectl get svc "${APP_NAME}" -n "${APP_NAMESPACE}"
  kubectl get ingress "${INGRESS_NAME}" -n "${APP_NAMESPACE}"
}

main() {
  require_command kubectl
  require_command helm
  require_kube_context
  require_cluster_access
  log "Using kube context: $(kubectl config current-context)"

  check_required_files
  ensure_namespaces
  apply_secrets
  install_mongodb
  install_app_chart --set clusterIssuer.enabled=false

  local ingress_address
  local ingress_host

  ingress_address="$(wait_for_ingress_address)"
  ingress_host="$(get_ingress_host)"
  log "Ingress address: ${ingress_address}"
  if [ -n "${ingress_host}" ]; then
    log "Ingress host: ${ingress_host}"
  fi

  confirm_dns "${ingress_address}"
  ensure_cert_manager
  install_app_chart --set clusterIssuer.enabled=true
  final_status

  log "Done. If you're using Ingress, check the Ingress address/hostname for access."
}

main "$@"
