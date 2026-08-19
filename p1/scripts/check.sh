#!/usr/bin/env bash
set -Exeu -o pipefail

expected_nodes=2
actual_nodes="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
ready_nodes="$(kubectl get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')"

kubectl get nodes -o wide

if [[ "${actual_nodes}" -ne "${expected_nodes}" || "${ready_nodes}" -ne "${expected_nodes}" ]]; then
  echo "Expected ${expected_nodes} Ready nodes; found ${ready_nodes}/${actual_nodes}." >&2
  exit 1
fi

echo "Part 1 verified: one K3s server and one K3s worker are Ready."
