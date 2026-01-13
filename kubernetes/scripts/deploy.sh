#!/usr/bin/env bash
set -euo pipefail


APP_NAMESPACE="${APP_NAMESPACE:-default}"
MONGODB_RELEASE_NAME="${MONGODB_RELEASE_NAME:-demo-mongo}"
MONGODB_NAMESPACE="${MONGODB_NAMESPACE:-default}"
MONGODB_CHART="${MONGODB_CHART:-bitnami/mongodb}"
MONGODB_HELM_VALUES_ARGS=()
if [ -f "kubernetes/helm/mongodb_values.yaml" ]; then
  MONGODB_HELM_VALUES_ARGS+=(-f "kubernetes/helm/mongodb_values.yaml")
fi
if [ -f "kubernetes/helm/mongodb_values_override.yaml" ]; then
  MONGODB_HELM_VALUES_ARGS+=(-f "kubernetes/helm/mongodb_values_override.yaml")
fi

# Preflight checks.
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH." >&2
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required but not found in PATH." >&2
  exit 1
fi

if ! kubectl config current-context >/dev/null 2>&1; then
  echo "kubectl context is not set. Run 'kubectl config use-context'." >&2
  exit 1
fi

if ! kubectl get ns >/dev/null 2>&1; then
  echo "Unable to reach the cluster with kubectl." >&2
  exit 1
fi

echo "Using kube context: $(kubectl config current-context)"

required_files=(
  "creds/secret-mongodb-auth.yaml"
  "creds/secret-mongodb-uri.yaml"
  "kubernetes/manifests/app/configmap.yaml"
  "kubernetes/manifests/app/deployment.yaml"
  "kubernetes/manifests/app/service.yaml"
  "kubernetes/manifests/app/ingress.yaml"
  "kubernetes/manifests/app/clusterissuer.yaml"
)
for file in "${required_files[@]}"; do
  if [ ! -f "${file}" ]; then
    echo "Missing required file: ${file}" >&2
    exit 1
  fi
done


# Ensure namespaces exist.
kubectl create namespace "${APP_NAMESPACE}" >/dev/null 2>&1 || true
kubectl create namespace "${MONGODB_NAMESPACE}" >/dev/null 2>&1 || true

# Apply Secrets before anything that depends on them.
kubectl apply -n "${MONGODB_NAMESPACE}" -f "creds/secret-mongodb-auth.yaml"
kubectl apply -n "${APP_NAMESPACE}" -f "creds/secret-mongodb-uri.yaml"

# kubectl create secret generic demo-mongo-auth \
#  --from-env-file="${ROOT_DIR}/creds/mongodb_auth.env" \
#  --dry-run=client -o yaml | kubectl apply -f -

# Install or upgrade MongoDB.
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install "${MONGODB_RELEASE_NAME}" "${MONGODB_CHART}" \
  -n "${MONGODB_NAMESPACE}" \
  --create-namespace \
  "${MONGODB_HELM_VALUES_ARGS[@]}"

# kubectl create secret generic demo-crm-mongodb-uri \
#   --from-env-file="${ROOT_DIR}/creds/mongo.env" \
#   --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/configmap.yaml"
kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/deployment.yaml"
kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/service.yaml"
kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/ingress.yaml"

# Wait for Ingress external address and confirm DNS is updated.
echo "Waiting for Ingress external address..."
INGRESS_ADDRESS=""
while [ -z "${INGRESS_ADDRESS}" ]; do
  INGRESS_ADDRESS="$(kubectl get ingress demo-crm -n "${APP_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -z "${INGRESS_ADDRESS}" ]; then
    INGRESS_ADDRESS="$(kubectl get ingress demo-crm -n "${APP_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  fi
  if [ -z "${INGRESS_ADDRESS}" ]; then
    echo "Ingress address not ready yet. Retrying in 5s..."
    sleep 5
  fi
done

INGRESS_HOST="$(kubectl get ingress demo-crm -n "${APP_NAMESPACE}" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
echo "Ingress address: ${INGRESS_ADDRESS}"
if [ -n "${INGRESS_HOST}" ]; then
  echo "Ingress host: ${INGRESS_HOST}"
fi

DNS_CONFIRM="${DNS_CONFIRM:-}"
if [ -z "${DNS_CONFIRM}" ]; then
  if [ -t 0 ]; then
    read -r -p "Has the DNS A record been updated to point to ${INGRESS_ADDRESS}? (y/N) " DNS_CONFIRM
  elif [ -r /dev/tty ]; then
    read -r -p "Has the DNS A record been updated to point to ${INGRESS_ADDRESS}? (y/N) " DNS_CONFIRM </dev/tty
  else
    echo "No interactive TTY available. Set DNS_CONFIRM=y to continue." >&2
    exit 1
  fi
fi
if [[ ! "${DNS_CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "Aborting. Update DNS and re-run."
  exit 1
fi

# Install cert-manager if missing, then apply ClusterIssuer and re-apply Ingress.
if ! kubectl get deployment cert-manager -n cert-manager >/dev/null 2>&1; then
  kubectl create namespace cert-manager >/dev/null 2>&1 || true
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --set installCRDs=true
  kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=120s
fi

kubectl apply -f "kubernetes/manifests/app/clusterissuer.yaml"
kubectl apply -n "${APP_NAMESPACE}" -f "kubernetes/manifests/app/ingress.yaml"

sleep 10
kubectl rollout status deployment/demo-crm -n "${APP_NAMESPACE}"
kubectl get svc demo-crm -n "${APP_NAMESPACE}"
kubectl get ingress demo-crm -n "${APP_NAMESPACE}"

echo "Done. If you're using Ingress, check the Ingress address/hostname for access."
