#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${1:-my-cluster}
LOCATION=${2:-europe-north1-c}

gcloud container clusters delete "$CLUSTER_NAME" \
  --location "$LOCATION"
