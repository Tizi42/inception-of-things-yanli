#!/usr/bin/env bash
set -Exeu -o pipefail

for required_command in awk kubectl tr wc; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "ERROR: required tool '${required_command}' was not found in PATH." >&2
    echo "Install it locally and rerun this script." >&2
    exit 127
  fi
done

expected_nodes=2
actual_nodes="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
ready_nodes="$(kubectl get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')"

kubectl get nodes -o wide

if [[ "${actual_nodes}" -ne "${expected_nodes}" || "${ready_nodes}" -ne "${expected_nodes}" ]]; then
  echo "Expected ${expected_nodes} Ready nodes; found ${ready_nodes}/${actual_nodes}." >&2
  exit 1
fi

echo "Part 1 verified: one K3s server and one K3s worker are Ready."
