#!/usr/bin/env bash
set -Eeux -o pipefail

readonly NODE_IP="${1:?server IP is required}"
readonly CONFIG_SOURCE="/vagrant/confs/k3s-server.yaml"
readonly CONFIG_TARGET="/etc/rancher/k3s/config.yaml"

for required_command in awk chmod chown cp curl install ip sed sh systemctl timeout; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "ERROR: required tool '${required_command}' was not found in PATH." >&2
    echo "Install it in the guest before provisioning and rerun Vagrant." >&2
    exit 127
  fi
done

private_iface="$(
  ip -o -4 addr show |
    awk -v ip="${NODE_IP}" '
      {
        split($4, address, "/")
        if (address[1] == ip && !found) {
          print $2
          found = 1
        }
      }
    '
)"
if [[ -z "${private_iface}" ]]; then
  echo "Cannot find the interface carrying ${NODE_IP}" >&2
  exit 1
fi

install -d -m 0755 /etc/rancher/k3s
sed \
  -e "s|__NODE_IP__|${NODE_IP}|g" \
  -e "s|__PRIVATE_IFACE__|${private_iface}|g" \
  "${CONFIG_SOURCE}" > "${CONFIG_TARGET}"
chmod 0600 "${CONFIG_TARGET}"

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_CHANNEL=stable \
  INSTALL_K3S_EXEC=server \
  sh -

systemctl enable --now k3s
timeout 180 bash -c 'until kubectl get --raw=/readyz >/dev/null 2>&1; do sleep 3; done'

install -d -m 0700 -o vagrant -g vagrant /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
chmod 0600 /home/vagrant/.kube/config

kubectl apply -k /vagrant/confs
kubectl -n iot-apps rollout status deployment/app1 --timeout=180s
kubectl -n iot-apps rollout status deployment/app2 --timeout=180s
kubectl -n iot-apps rollout status deployment/app3 --timeout=180s

echo "K3s and the three ingress-routed applications are ready on ${NODE_IP}."
