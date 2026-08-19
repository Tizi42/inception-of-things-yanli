#!/usr/bin/env bash
set -Eeux -o pipefail

readonly SERVER_IP="${1:-192.168.56.110}"

kubectl -n iot-apps get deployments,pods,services,ingress -o wide

app2_ready="$(kubectl -n iot-apps get deployment app2 -o jsonpath='{.status.readyReplicas}')"
if [[ "${app2_ready:-0}" -ne 3 ]]; then
  echo "app2 must have 3 Ready replicas; found ${app2_ready:-0}." >&2
  exit 1
fi

curl -fsS -H 'Host: app1.com' "http://${SERVER_IP}/" | grep -q 'Hello from app1'
curl -fsS -H 'Host: app2.com' "http://${SERVER_IP}/" | grep -q 'Hello from app2'
curl -fsS -H 'Host: unknown.example' "http://${SERVER_IP}/" | grep -q 'Hello from app3'

echo "Part 2 verified: app1.com, app2.com (3 replicas), and the app3 default all route correctly."
