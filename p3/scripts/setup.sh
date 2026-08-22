#!/usr/bin/env bash
set -Eeux -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
readonly CLUSTER_NAME="${IOT_CLUSTER_NAME:-iot}"
readonly LOGIN="${IOT_LOGIN:-yanli}"
readonly REPO_URL="https://github.com/Tizi42/inception-of-things-yanli"
readonly REVISION="${IOT_GIT_REVISION:-main}"
readonly APP_TEMPLATE="${ROOT_DIR}/p3/confs/argocd-application.yaml.tmpl"
# shellcheck source=requirements.sh
source "${ROOT_DIR}/p3/scripts/requirements.sh"

require_commands awk curl docker git grep k3d kubectl sed timeout
require_docker_access

if [[ ! "${REPO_URL}" =~ ^https://github\.com/[^/]+/[^/]+(\.git)?$ ]]; then
  echo "The configured public GitHub repository is invalid: ${REPO_URL}" >&2
  exit 1
fi

repo_name="$(basename "${REPO_URL}" .git)"
if [[ "${repo_name,,}" != *"${LOGIN,,}"* ]]; then
  echo "The repository name '${repo_name}' must contain the team login '${LOGIN}'." >&2
  exit 1
fi

git ls-remote "${REPO_URL}" "${REVISION}" | grep -q . || {
  echo "The public repository or revision '${REVISION}' is not reachable: ${REPO_URL}" >&2
  exit 1
}

if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -Fxq "${CLUSTER_NAME}"; then
  k3d cluster create "${CLUSTER_NAME}" \
    --servers 1 \
    --agents 0 \
    --port "8888:30080@server:0" \
    --wait
fi

kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
kubectl wait --for=condition=Ready node --all --timeout=180s

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=300s
kubectl -n argocd wait --for=condition=Ready pod --all --timeout=300s
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

escaped_repo="${REPO_URL//&/\\&}"
escaped_revision="${REVISION//&/\\&}"
sed \
  -e "s|__REPO_URL__|${escaped_repo}|g" \
  -e "s|__REVISION__|${escaped_revision}|g" \
  "${APP_TEMPLATE}" | kubectl apply -f -

timeout 360 bash -c \
  'until [[ "$(kubectl -n argocd get application iot-app -o jsonpath="{.status.sync.status}" 2>/dev/null)" == "Synced" && "$(kubectl -n argocd get application iot-app -o jsonpath="{.status.health.status}" 2>/dev/null)" == "Healthy" ]]; do sleep 5; done'
timeout 180 bash -c 'until curl -fsS http://127.0.0.1:8888/ | grep -q '"'"'"message"'"'"'; do sleep 3; done'

echo "Part 3 is ready. Application: http://127.0.0.1:8888"
echo "Run p3/scripts/argocd-ui.sh to expose the Argo CD UI on https://127.0.0.1:8080."
