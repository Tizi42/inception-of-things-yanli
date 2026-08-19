#!/usr/bin/env bash
set -Eeux -o pipefail

readonly VERSION="${1:?usage: switch-version.sh v1|v2}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
readonly DEPLOYMENT="${ROOT_DIR}/p3/confs/app/deployment.yaml"
readonly PUSH_REPO="git@github.com:Tizi42/inception-of-things-yanli.git"
readonly PUSH_BRANCH="${IOT_GIT_REVISION:-main}"

if [[ ! "${VERSION}" =~ ^v[12]$ ]]; then
  echo "Version must be v1 or v2." >&2
  exit 1
fi

git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null
git -C "${ROOT_DIR}" config user.name "${IOT_GIT_NAME:-IoT Defense}"
git -C "${ROOT_DIR}" config user.email "${IOT_GIT_EMAIL:-iot-defense@localhost}"

sed -i -E "s|(image: wil42/playground:)v[12]|\\1${VERSION}|" "${DEPLOYMENT}"
git -C "${ROOT_DIR}" add p3/confs/app/deployment.yaml

if git -C "${ROOT_DIR}" diff --cached --quiet; then
  echo "The Git repository already declares ${VERSION}."
else
  git -C "${ROOT_DIR}" commit -m "deploy playground ${VERSION}"
fi

git -C "${ROOT_DIR}" push "${PUSH_REPO}" "HEAD:${PUSH_BRANCH}"

if kubectl -n argocd get application iot-app >/dev/null 2>&1; then
  kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  timeout 360 bash -c \
    'until [[ "$(kubectl -n argocd get application iot-app -o jsonpath="{.status.sync.status}")" == "Synced" && "$(kubectl -n dev get deployment playground -o jsonpath="{.spec.template.spec.containers[0].image}")" == "wil42/playground:'"${VERSION}"'" ]]; do sleep 5; done'
  kubectl -n dev rollout status deployment/playground --timeout=180s
  curl -fsS http://127.0.0.1:8888/
  printf '\n'
fi
