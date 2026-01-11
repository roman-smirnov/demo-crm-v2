#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${1:-my-cluster}
LOCATION=${2:-europe-north1-b}
NUM_NODES=${3:-2}
MACHINE_TYPE=${4:-n2-standard-2}
DISK_SIZE=${5:-50}
RELEASE_CHANNEL=${6:-regular}

# create the GKE cluster
gcloud container clusters create "$CLUSTER_NAME" \
  --location "$LOCATION" \
  --num-nodes "$NUM_NODES" \
  --machine-type "$MACHINE_TYPE" \
  --disk-size "$DISK_SIZE" \
  --release-channel "$RELEASE_CHANNEL"

# connect kubectl to the new cluster
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --location "$LOCATION"
