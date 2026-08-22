#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
readonly STATE_FILE="${ROOT_DIR}/bonus/.state/runtime.env"
# shellcheck source=requirements.sh
source "${ROOT_DIR}/bonus/scripts/requirements.sh"
require_commands base64 kubectl

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "Bonus setup is incomplete: ${STATE_FILE} has not been generated." >&2
  echo "Run bonus/scripts/setup.sh and make sure it finishes with 'Bonus ready'." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${STATE_FILE}"

password="$(kubectl -n gitlab get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 --decode)"
echo "GitLab URL: http://gitlab.${GITLAB_DOMAIN}"
echo "Username: root"
echo "Password: ${password}"
