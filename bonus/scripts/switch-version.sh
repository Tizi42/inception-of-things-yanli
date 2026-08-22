#!/usr/bin/env bash
set -Eeuo pipefail

readonly VERSION="${1:?usage: switch-version.sh v1|v2}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
readonly STATE_FILE="${ROOT_DIR}/bonus/.state/runtime.env"
# shellcheck source=requirements.sh
source "${ROOT_DIR}/bonus/scripts/requirements.sh"

require_commands base64 curl jq kubectl sed timeout

if [[ ! "${VERSION}" =~ ^v[12]$ ]]; then
  echo "Version must be v1 or v2." >&2
  exit 1
fi
if [[ ! -f "${STATE_FILE}" ]]; then
  echo "Bonus setup is incomplete: ${STATE_FILE} has not been generated." >&2
  echo "Run bonus/scripts/setup.sh and make sure it finishes with 'Bonus ready'." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${STATE_FILE}"
readonly API_URL="http://gitlab.${GITLAB_DOMAIN}/api/v4"

file_json="$(curl -fsS \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${API_URL}/projects/${GITLAB_PROJECT_ID}/repository/files/deployment.yaml?ref=main")"
current_content="$(jq -r '.content' <<<"${file_json}" | base64 --decode)"
updated_content="$(sed -E "s|(image: wil42/playground:)v[12]|\\1${VERSION}|" <<<"${current_content}")"

if [[ "${current_content}" == "${updated_content}" ]]; then
  echo "The local GitLab repository already declares ${VERSION}."
else
  payload="$(jq -n \
    --arg branch main \
    --arg message "deploy playground ${VERSION}" \
    --arg content "${updated_content}" \
    '{branch: $branch, commit_message: $message, content: $content}')"
  curl -fsS --request PUT \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --header 'Content-Type: application/json' \
    --data "${payload}" \
    "${API_URL}/projects/${GITLAB_PROJECT_ID}/repository/files/deployment.yaml" >/dev/null
fi

kubectl -n argocd annotate application iot-app-gitlab argocd.argoproj.io/refresh=hard --overwrite >/dev/null
timeout 600 bash -c \
  'until [[ "$(kubectl -n argocd get application iot-app-gitlab -o jsonpath="{.status.sync.status}")" == "Synced" && "$(kubectl -n dev get deployment playground -o jsonpath="{.spec.template.spec.containers[0].image}")" == "wil42/playground:'"${VERSION}"'" ]]; do sleep 10; done'
kubectl -n dev rollout status deployment/playground --timeout=180s
curl -fsS http://127.0.0.1:8888/
printf '\n'
