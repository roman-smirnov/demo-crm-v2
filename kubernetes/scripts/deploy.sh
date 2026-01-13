#!/usr/bin/env bash
set -euo pipefail


# kubectl create secret generic demo-mongo-auth \
#  --from-env-file="${ROOT_DIR}/creds/mongodb_auth.env" \
#  --dry-run=client -o yaml | kubectl apply -f -

# helm upgrade --install "${MONGODB_RELEASE_NAME}" "${MONGODB_CHART}" \
  # "${MONGODB_HELM_VALUES_ARGS[@]}"

# kubectl create secret generic demo-crm-mongodb-uri \
#   --from-env-file="${ROOT_DIR}/creds/mongo.env" \
#   --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "kubernetes/manifests/app/configmap.yaml"
kubectl apply -f "kubernetes/manifests/app/deployment.yaml"
kubectl apply -f "kubernetes/manifests/app/service.yaml"
kubectl apply -f "kubernetes/manifests/app/ingress.yaml"

sleep 5

kubectl rollout status deployment/demo-crm

sleep 10

kubectl get svc demo-crm

kubectl get ingress demo-crm


echo "Done. If you're using Ingress, check the Ingress address/hostname for access."
