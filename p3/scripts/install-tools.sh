#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
# shellcheck source=requirements.sh
source "${ROOT_DIR}/p3/scripts/requirements.sh"

echo "Automatic tool installation is disabled; this script only checks prerequisites."
require_commands awk base64 curl docker git grep helm jq k3d kubectl openssl sed timeout
require_docker_access
echo "All Part 3 and bonus prerequisites are available to the current user."
