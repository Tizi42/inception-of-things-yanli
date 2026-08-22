#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
# shellcheck source=requirements.sh
source "${ROOT_DIR}/bonus/scripts/requirements.sh"

require_commands awk base64 curl docker git grep helm jq k3d kubectl openssl sed timeout
require_docker_access

echo "Bonus prerequisites are available. No tools or system resources were installed."
echo "Run: cd ${ROOT_DIR} && bash bonus/scripts/setup.sh"
