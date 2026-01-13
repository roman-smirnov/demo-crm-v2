#!/usr/bin/env bash
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-default}"
MONGODB_RELEASE_NAME="${MONGODB_RELEASE_NAME:-demo-mongo}"
MONGODB_NAMESPACE="${MONGODB_NAMESPACE:-default}"
MONGODB_CHART="${MONGODB_CHART:-bitnami/mongodb}"

APP_NAME="demo-crm"
INGRESS_NAME="demo-crm"

MONGODB_VALUES_FILE="kubernetes/helm/mongodb_values.yaml"
MONGODB_VALUES_OVERRIDE_FILE="kubernetes/helm/mongodb_values_override.yaml"

MONGODB_AUTH_ENV_FILE="creds/mongodb_auth.env"
MONGODB_URI_ENV_FILE="creds/mongo.env"
MONGODB_AUTH_SECRET_NAME="demo-mongo-auth"
MONGODB_URI_SECRET_NAME="demo-crm-mongodb-uri"

REQUIRED_FILES=(
  "${MONGODB_AUTH_ENV_FILE}"
  "${MONGODB_URI_ENV_FILE}"
  "kubernetes/manifests/app/configmap.yaml"
  "kubernetes/manifests/app/deployment.yaml"
  "kubernetes/manifests/app/service.yaml"
  "kubernetes/manifests/app/ingress.yaml"
  "kubernetes/manifests/app/clusterissuer.yaml"
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

check_required_files() {
  local file
  for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${file}" ]; then
      die "Missing required file: ${file}"
    fi
  done
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

  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update
  helm upgrade --install "${MONGODB_RELEASE_NAME}" "${MONGODB_CHART}" \
    -n "${MONGODB_NAMESPACE}" \
    --create-namespace \
    "${values_args[@]}"
}

apply_app_manifests() {
  kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/configmap.yaml"
  kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/deployment.yaml"
  kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/service.yaml"
  kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/ingress.yaml"
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
  if ! kubectl get deployment cert-manager -n cert-manager >/dev/null 2>&1; then
    kubectl create namespace cert-manager >/dev/null 2>&1 || true
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --set installCRDs=true
    kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
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
  apply_app_manifests

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
  kubectl apply -f "kubernetes/manifests/app/clusterissuer.yaml"
  kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/ingress.yaml"
  final_status

  log "Done. If you're using Ingress, check the Ingress address/hostname for access."
}

main "$@"
