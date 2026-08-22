#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
# shellcheck source=../../scripts/lib/requirements.sh
source "${ROOT_DIR}/scripts/lib/requirements.sh"

require_commands awk base64 curl docker git grep helm jq k3d kubectl openssl sed timeout
require_docker_access

echo "Bonus prerequisites are available. No tools or system resources were installed."
echo "Run: cd ${ROOT_DIR} && bash bonus/scripts/setup.sh"
