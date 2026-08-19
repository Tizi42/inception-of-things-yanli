#!/usr/bin/env bash
set -Eeux -o pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this installer as root: sudo $0" >&2
  exit 1
fi

readonly TARGET_USER="${IOT_TARGET_USER:-${SUDO_USER:-${USER}}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git gnupg jq lsb-release openssl tar

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

architecture="$(dpkg --print-architecture)"
codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME}")"
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
  "${architecture}" "${codename}" > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker "${TARGET_USER}"

case "$(uname -m)" in
  x86_64) binary_arch="amd64" ;;
  aarch64|arm64) binary_arch="arm64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

kubectl_version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${binary_arch}/kubectl"
curl -fsSLo /tmp/kubectl.sha256 "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${binary_arch}/kubectl.sha256"
printf '%s  %s\n' "$(cat /tmp/kubectl.sha256)" /tmp/kubectl | sha256sum --check --status
install -m 0755 /tmp/kubectl /usr/local/bin/kubectl

curl -fsSLo /tmp/k3d-install.sh https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh
bash /tmp/k3d-install.sh

argocd_version="$(curl -fsSL https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)"
curl -fsSLo /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/v${argocd_version}/argocd-linux-${binary_arch}"
install -m 0555 /tmp/argocd /usr/local/bin/argocd

curl -fsSLo /tmp/get-helm-4.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 0700 /tmp/get-helm-4.sh
/tmp/get-helm-4.sh

echo "Installed Docker, kubectl ${kubectl_version}, the current stable k3d, Argo CD ${argocd_version}, and Helm."
echo "Log out and back in once so ${TARGET_USER} receives Docker group access."
