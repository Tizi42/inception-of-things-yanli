#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
readonly STATE_FILE="${ROOT_DIR}/bonus/.state/runtime.env"

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "Bonus setup is incomplete: ${STATE_FILE} has not been generated." >&2
  echo "Run bonus/scripts/setup.sh and make sure it finishes with 'Bonus ready'." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${STATE_FILE}"

kubectl get namespaces argocd dev gitlab
kubectl -n gitlab get pods
kubectl -n argocd get application iot-app-gitlab
kubectl -n dev get deployments,pods,services -o wide

curl -fsS "http://gitlab.${GITLAB_DOMAIN}/-/readiness" >/dev/null
sync_status="$(kubectl -n argocd get application iot-app-gitlab -o jsonpath='{.status.sync.status}')"
health_status="$(kubectl -n argocd get application iot-app-gitlab -o jsonpath='{.status.health.status}')"
image="$(kubectl -n dev get deployment playground -o jsonpath='{.spec.template.spec.containers[0].image}')"
response="$(curl -fsS http://127.0.0.1:8888/)"

[[ "${sync_status}" == "Synced" ]]
[[ "${health_status}" == "Healthy" ]]
[[ "${image}" =~ wil42/playground:v[12]$ ]]
grep -q '"status":"ok"' <<<"${response}"

printf 'Bonus verified: local GitLab is ready; Argo CD is %s/%s and serves %s.\n' \
  "${sync_status}" "${health_status}" "${image}"
