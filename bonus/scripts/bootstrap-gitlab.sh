#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
readonly DOMAIN="${IOT_GITLAB_DOMAIN:-${IOT_BONUS_IP:-192.168.56.120}.nip.io}"
readonly GITLAB_URL="http://gitlab.${DOMAIN}"
readonly API_URL="${GITLAB_URL}/api/v4"
readonly LOGIN="${IOT_LOGIN:-yanli}"
readonly PROJECT_NAME="inception-of-things-${LOGIN}"
readonly PROJECT_PATH="root%2F${PROJECT_NAME}"
readonly STATE_DIR="${ROOT_DIR}/bonus/.state"
readonly STATE_FILE="${STATE_DIR}/runtime.env"
# shellcheck source=requirements.sh
source "${ROOT_DIR}/bonus/scripts/requirements.sh"

require_commands base64 curl git jq kubectl openssl sed timeout

echo "Waiting for the local GitLab API (this can take 20-30 minutes on first boot)..."
timeout 1800 bash -c "until curl -fsS '${GITLAB_URL}/-/readiness' >/dev/null; do sleep 15; done"

mkdir -p "${STATE_DIR}"
chmod 0700 "${STATE_DIR}"

token=""
if [[ -f "${STATE_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
  token="${GITLAB_TOKEN:-}"
fi

if [[ -z "${token}" ]] || ! curl -fsS --header "PRIVATE-TOKEN: ${token}" "${API_URL}/user" >/dev/null; then
  kubectl -n gitlab wait --for=condition=Ready pod -l app=toolbox --timeout=1800s
  toolbox_pod="$(kubectl -n gitlab get pod -l app=toolbox -o jsonpath='{.items[0].metadata.name}')"
  token="glpat-$(openssl rand -hex 24)"
  ruby_script="$(mktemp)"
  printf '%s\n' \
    "user = User.find_by_username('root')" \
    "user.personal_access_tokens.where(name: 'iot-bootstrap').destroy_all" \
    "token = user.personal_access_tokens.create!(scopes: ['api', 'read_repository', 'write_repository'], name: 'iot-bootstrap', expires_at: 365.days.from_now)" \
    "token.set_token('${token}')" \
    "token.save!" > "${ruby_script}"
  kubectl -n gitlab exec -i "${toolbox_pod}" -- tee /tmp/iot-create-token.rb < "${ruby_script}" >/dev/null
  kubectl -n gitlab exec "${toolbox_pod}" -- bash -lc 'cd /srv/gitlab && bin/rails runner /tmp/iot-create-token.rb'
  if [[ -f "${ruby_script}" && "${ruby_script}" == /tmp/* ]]; then
    rm -f -- "${ruby_script}"
  fi
fi

project_json="$(curl -fsS --header "PRIVATE-TOKEN: ${token}" "${API_URL}/projects/${PROJECT_PATH}" 2>/dev/null || true)"
if [[ -z "${project_json}" ]]; then
  project_json="$(curl -fsS --request POST \
    --header "PRIVATE-TOKEN: ${token}" \
    --data-urlencode "name=${PROJECT_NAME}" \
    --data-urlencode "path=${PROJECT_NAME}" \
    --data "visibility=private" \
    --data "initialize_with_readme=true" \
    --data "default_branch=main" \
    "${API_URL}/projects")"
fi
project_id="$(jq -er '.id' <<<"${project_json}")"
repo_url="${GITLAB_URL}/root/${PROJECT_NAME}.git"

work_dir="$(mktemp -d)"
cleanup() {
  if [[ -n "${work_dir:-}" && -d "${work_dir}" && "${work_dir}" == /tmp/* ]]; then
    rm -rf -- "${work_dir}"
  fi
}
trap cleanup EXIT

auth_header="Authorization: Basic $(printf 'root:%s' "${token}" | base64 -w0)"
git -c "http.extraHeader=${auth_header}" clone "${repo_url}" "${work_dir}/repo"
cp "${ROOT_DIR}/bonus/confs/app/"*.yaml "${work_dir}/repo/"
git -C "${work_dir}/repo" config user.name "IoT GitLab Bootstrap"
git -C "${work_dir}/repo" config user.email "iot-gitlab@localhost"
git -C "${work_dir}/repo" add deployment.yaml service.yaml kustomization.yaml
if ! git -C "${work_dir}/repo" diff --cached --quiet; then
  git -C "${work_dir}/repo" commit -m "bootstrap GitOps application v1"
  git -C "${work_dir}/repo" -c "http.extraHeader=${auth_header}" push origin main
fi

kubectl -n argocd create secret generic gitlab-iot-repo \
  --from-literal=type=git \
  --from-literal=url="${repo_url}" \
  --from-literal=username=root \
  --from-literal=password="${token}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret gitlab-iot-repo argocd.argoproj.io/secret-type=repository --overwrite

escaped_repo="${repo_url//&/\\&}"
sed "s|__REPO_URL__|${escaped_repo}|g" \
  "${ROOT_DIR}/bonus/confs/argocd-application.yaml.tmpl" | kubectl apply -f -

{
  printf 'GITLAB_DOMAIN=%q\n' "${DOMAIN}"
  printf 'GITLAB_TOKEN=%q\n' "${token}"
  printf 'GITLAB_PROJECT_ID=%q\n' "${project_id}"
  printf 'GITLAB_REPO_URL=%q\n' "${repo_url}"
} > "${STATE_FILE}"
chmod 0600 "${STATE_FILE}"

echo "Local GitLab project and Argo CD repository credentials are configured."
