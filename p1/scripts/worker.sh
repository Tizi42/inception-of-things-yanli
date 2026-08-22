#!/usr/bin/env bash
set -Eeux -o pipefail

readonly NODE_IP="${1:?worker IP is required}"
readonly SERVER_IP="${2:?server IP is required}"
readonly CLUSTER_TOKEN="${3:?cluster token is required}"
readonly CONFIG_SOURCE="/vagrant/confs/worker.yaml"
readonly CONFIG_TARGET="/etc/rancher/k3s/config.yaml"

for required_command in awk chmod curl install ip sed sh systemctl timeout; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "ERROR: required tool '${required_command}' was not found in PATH." >&2
    echo "Install it in the guest before provisioning and rerun Vagrant." >&2
    exit 127
  fi
done

private_iface="$(ip -o -4 addr show | awk -v ip="${NODE_IP}" '$4 ~ ("^" ip "/") {print $2; exit}')"
if [[ -z "${private_iface}" ]]; then
  echo "Cannot find the interface carrying ${NODE_IP}" >&2
  exit 1
fi

timeout 180 bash -c "until curl -kfsS https://${SERVER_IP}:6443/ping >/dev/null; do sleep 3; done"

install -d -m 0755 /etc/rancher/k3s
sed \
  -e "s|__NODE_IP__|${NODE_IP}|g" \
  -e "s|__SERVER_IP__|${SERVER_IP}|g" \
  -e "s|__CLUSTER_TOKEN__|${CLUSTER_TOKEN}|g" \
  -e "s|__PRIVATE_IFACE__|${private_iface}|g" \
  "${CONFIG_SOURCE}" > "${CONFIG_TARGET}"
chmod 0600 "${CONFIG_TARGET}"

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_CHANNEL=stable \
  INSTALL_K3S_EXEC=agent \
  sh -

systemctl enable --now k3s-agent
timeout 180 bash -c 'until systemctl is-active --quiet k3s-agent; do sleep 3; done'

echo "K3s worker is connected to ${SERVER_IP}:6443 from ${NODE_IP} (${private_iface})."
