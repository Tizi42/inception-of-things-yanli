#!/usr/bin/env bash
set -Eeux -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
# shellcheck source=requirements.sh
source "${ROOT_DIR}/p3/scripts/requirements.sh"
require_commands base64 kubectl

password="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode)"
echo "Argo CD username: admin"
echo "Argo CD password: ${password}"
echo "Open https://127.0.0.1:8080 and accept the local self-signed certificate."
kubectl -n argocd port-forward service/argocd-server 8080:443
