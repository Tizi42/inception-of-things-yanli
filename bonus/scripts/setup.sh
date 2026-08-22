#!/usr/bin/env bash
set -Eeux -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
readonly CLUSTER_NAME="${IOT_BONUS_CLUSTER_NAME:-iot-bonus}"
readonly EXTERNAL_IP="${IOT_BONUS_IP:-192.168.56.120}"
readonly DOMAIN="${IOT_GITLAB_DOMAIN:-${EXTERNAL_IP}.nip.io}"
readonly GITLAB_CHART_VERSION="${IOT_GITLAB_CHART_VERSION:-9.11.12}"
readonly VALUES_TEMPLATE="${ROOT_DIR}/bonus/confs/gitlab-values.yaml.tmpl"
# shellcheck source=requirements.sh
source "${ROOT_DIR}/bonus/scripts/requirements.sh"

require_commands awk base64 curl docker git grep helm jq k3d kubectl openssl sed timeout
require_docker_access

if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -Fxq "${CLUSTER_NAME}"; then
  k3d cluster create "${CLUSTER_NAME}" \
    --servers 1 \
    --agents 1 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --port "2222:32022@agent:0" \
    --port "8888:30080@agent:0" \
    --wait
fi

kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=180s

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=300s
kubectl -n argocd wait --for=condition=Ready pod --all --timeout=300s

values_file="$(mktemp)"
cleanup() {
  if [[ -n "${values_file:-}" && -f "${values_file}" && "${values_file}" == /tmp/* ]]; then
    rm -f -- "${values_file}"
  fi
}
trap cleanup EXIT

sed \
  -e "s|__DOMAIN__|${DOMAIN}|g" \
  -e "s|__EXTERNAL_IP__|${EXTERNAL_IP}|g" \
  "${VALUES_TEMPLATE}" > "${values_file}"

helm repo add gitlab https://charts.gitlab.io --force-update
helm repo update gitlab
helm upgrade --install gitlab gitlab/gitlab \
  --version "${GITLAB_CHART_VERSION}" \
  --namespace gitlab \
  --create-namespace \
  --values "${values_file}" \
  --timeout 30m

IOT_GITLAB_DOMAIN="${DOMAIN}" bash "${ROOT_DIR}/bonus/scripts/bootstrap-gitlab.sh"

timeout 600 bash -c \
  'until [[ "$(kubectl -n argocd get application iot-app-gitlab -o jsonpath="{.status.sync.status}" 2>/dev/null)" == "Synced" && "$(kubectl -n argocd get application iot-app-gitlab -o jsonpath="{.status.health.status}" 2>/dev/null)" == "Healthy" ]]; do sleep 10; done'
timeout 180 bash -c 'until curl -fsS http://127.0.0.1:8888/ | grep -q '"'"'"message"'"'"'; do sleep 3; done'

echo "Bonus ready: GitLab http://gitlab.${DOMAIN}, app http://127.0.0.1:8888"
