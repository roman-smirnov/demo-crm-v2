#!/usr/bin/env bash
set -euo pipefail

APP_NAMESPACE="${APP_NAMESPACE:-app}"
APP_NAME="${APP_NAME:-demo-crm}"
JOB_NAME="${JOB_NAME:-demo-crm-load-test}"
DURATION="${DURATION:-1m}"
CONCURRENCY="${CONCURRENCY:-25}"
TARGET_URL="${TARGET_URL:-http://${APP_NAME}.${APP_NAMESPACE}.svc.cluster.local/}"
HEY_IMAGE="${HEY_IMAGE:-demisto/rakyll-hey:1.0.0.108484}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-5m}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

usage() {
  cat <<'EOF'
Usage: load_test.sh [--help]

Environment variables:
  APP_NAMESPACE=app
  APP_NAME=demo-crm
  JOB_NAME=demo-crm-load-test
  DURATION=1m
  CONCURRENCY=25
  TARGET_URL=http://demo-crm.app.svc.cluster.local/
  HEY_IMAGE=demisto/rakyll-hey:1.0.0.108484
  WAIT_TIMEOUT=5m
  POLL_INTERVAL=5

Examples:
  APP_NAMESPACE=app ./kubernetes/scripts/load_test.sh
  DURATION=1m CONCURRENCY=25 ./kubernetes/scripts/load_test.sh
  TARGET_URL=https://your-hostname.example.com/ ./kubernetes/scripts/load_test.sh
  HEY_IMAGE=demisto/rakyll-hey:1.0.0.108484 ./kubernetes/scripts/load_test.sh
EOF
}

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

duration_to_seconds() {
  local value="$1"
  local number
  local unit

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
    return 0
  fi

  if [[ "$value" =~ ^[0-9]+[smh]$ ]]; then
    number="${value%[smh]}"
    unit="${value: -1}"
    case "$unit" in
      s) echo "$number" ;;
      m) echo $((number * 60)) ;;
      h) echo $((number * 3600)) ;;
    esac
    return 0
  fi

  return 1
}

collect_job_diagnostics() {
  log "Job status:"
  kubectl get job "${JOB_NAME}" -n "${APP_NAMESPACE}" -o wide || true
  kubectl describe job "${JOB_NAME}" -n "${APP_NAMESPACE}" || true

  log "Pods for job ${JOB_NAME}:"
  kubectl get pods -n "${APP_NAMESPACE}" -l job-name="${JOB_NAME}" -o wide || true

  local pod_name
  pod_name="$(kubectl get pods -n "${APP_NAMESPACE}" -l job-name="${JOB_NAME}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -n "${pod_name}" ]; then
    kubectl describe pod "${pod_name}" -n "${APP_NAMESPACE}" || true
    kubectl logs "${pod_name}" -n "${APP_NAMESPACE}" || true
  fi
}

wait_for_job() {
  local timeout_seconds="$1"
  local start
  local succeeded
  local failed

  start="$(date +%s)"
  while true; do
    succeeded="$(kubectl get job "${JOB_NAME}" -n "${APP_NAMESPACE}" \
      -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$(kubectl get job "${JOB_NAME}" -n "${APP_NAMESPACE}" \
      -o jsonpath='{.status.failed}' 2>/dev/null || true)"

    succeeded="${succeeded:-0}"
    failed="${failed:-0}"

    if [ "${succeeded}" -gt 0 ]; then
      return 0
    fi
    if [ "${failed}" -gt 0 ]; then
      return 1
    fi

    local now
    now="$(date +%s)"
    if [ $(( now - start )) -ge "${timeout_seconds}" ]; then
      return 2
    fi

    sleep "${POLL_INTERVAL}"
  done
}

main() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  if [ "$#" -gt 0 ]; then
    usage
    die "Unknown arguments: $*"
  fi

  if ! timeout_seconds="$(duration_to_seconds "${WAIT_TIMEOUT}")"; then
    usage
    die "WAIT_TIMEOUT must be an integer seconds or include s/m/h (e.g. 300, 5m)."
  fi

  if ! [[ "${POLL_INTERVAL}" =~ ^[0-9]+$ ]] || [ "${POLL_INTERVAL}" -le 0 ]; then
    usage
    die "POLL_INTERVAL must be a positive integer number of seconds."
  fi

  require_command kubectl
  require_kube_context

  if ! kubectl get svc "${APP_NAME}" -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
    die "Service ${APP_NAME} not found in namespace ${APP_NAMESPACE}."
  fi

  kubectl delete job "${JOB_NAME}" -n "${APP_NAMESPACE}" --ignore-not-found

  cat <<EOF | kubectl apply -n "${APP_NAMESPACE}" -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: hey
          image: ${HEY_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["hey"]
          args:
            - -z
            - "${DURATION}"
            - -c
            - "${CONCURRENCY}"
            - "${TARGET_URL}"
EOF

  log "Running load test against ${TARGET_URL} for ${DURATION} with ${CONCURRENCY} concurrent clients."
  if wait_for_job "${timeout_seconds}"; then
    kubectl logs job/"${JOB_NAME}" -n "${APP_NAMESPACE}"
  else
    case "$?" in
      1)
        log "Load test job failed."
        ;;
      2)
        log "Load test job timed out after ${WAIT_TIMEOUT}."
        ;;
    esac
    collect_job_diagnostics
    exit 1
  fi
  kubectl delete job "${JOB_NAME}" -n "${APP_NAMESPACE}" --ignore-not-found
}

main "$@"
