#!/usr/bin/env bash
set -Eeux -o pipefail

kubectl get namespaces argocd dev
kubectl -n argocd get application iot-app
kubectl -n dev get deployments,pods,services -o wide

sync_status="$(kubectl -n argocd get application iot-app -o jsonpath='{.status.sync.status}')"
health_status="$(kubectl -n argocd get application iot-app -o jsonpath='{.status.health.status}')"
image="$(kubectl -n dev get deployment playground -o jsonpath='{.spec.template.spec.containers[0].image}')"
response="$(curl -fsS http://127.0.0.1:8888/)"

[[ "${sync_status}" == "Synced" ]]
[[ "${health_status}" == "Healthy" ]]
[[ "${image}" =~ wil42/playground:v[12]$ ]]
grep -q '"status":"ok"' <<<"${response}"

printf 'Part 3 verified: Argo CD is %s/%s and serves %s with response %s\n' \
  "${sync_status}" "${health_status}" "${image}" "${response}"

