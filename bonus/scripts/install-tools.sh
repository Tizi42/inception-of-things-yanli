#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: this installer supports Linux guests only." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "ERROR: cannot identify the guest operating system." >&2
  exit 1
fi

# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "ERROR: this installer supports Ubuntu guests only; detected '${ID:-unknown}'." >&2
  exit 1
fi

if (( EUID == 0 )); then
  readonly TARGET_USER="${SUDO_USER:-root}"
  readonly -a ROOT=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: sudo is required inside the bonus VM." >&2
    exit 127
  fi
  sudo -v
  readonly TARGET_USER="${USER}"
  readonly -a ROOT=(sudo)
fi

if ! id "${TARGET_USER}" >/dev/null 2>&1; then
  echo "ERROR: target user '${TARGET_USER}' does not exist." >&2
  exit 1
fi

readonly TEMP_DIR="$(mktemp -d)"
cleanup() {
  if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" && "${TEMP_DIR}" == /tmp/* ]]; then
    rm -rf -- "${TEMP_DIR}"
  fi
}
trap cleanup EXIT

echo "Installing base packages..."
"${ROOT[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update
readonly -a BASE_PACKAGES=(
  bash
  ca-certificates
  coreutils
  curl
  findutils
  gawk
  git
  gnupg
  grep
  iproute2
  iptables
  jq
  openssl
  sed
  tar
  xz-utils
)
"${ROOT[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${BASE_PACKAGES[@]}"

echo "Configuring Docker's official Ubuntu repository..."
"${ROOT[@]}" install -m 0755 -d /etc/apt/keyrings
curl --proto '=https' --tlsv1.2 -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${TEMP_DIR}/docker.asc"
"${ROOT[@]}" install -o root -g root -m 0644 "${TEMP_DIR}/docker.asc" /etc/apt/keyrings/docker.asc

readonly UBUNTU_SUITE="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [[ -z "${UBUNTU_SUITE}" ]]; then
  echo "ERROR: Ubuntu did not provide a repository codename." >&2
  exit 1
fi

{
  printf 'Types: deb\n'
  printf 'URIs: https://download.docker.com/linux/ubuntu\n'
  printf 'Suites: %s\n' "${UBUNTU_SUITE}"
  printf 'Components: stable\n'
  printf 'Architectures: %s\n' "$(dpkg --print-architecture)"
  printf 'Signed-By: /etc/apt/keyrings/docker.asc\n'
} > "${TEMP_DIR}/docker.sources"
"${ROOT[@]}" install -o root -g root -m 0644 "${TEMP_DIR}/docker.sources" /etc/apt/sources.list.d/docker.sources

declare -a conflicting_packages=()
for package in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
  if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null |
    grep -Fqx 'install ok installed'; then
    conflicting_packages+=("${package}")
  fi
done
if (( ${#conflicting_packages[@]} > 0 )); then
  echo "Removing packages that conflict with Docker CE: ${conflicting_packages[*]}"
  "${ROOT[@]}" env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${conflicting_packages[@]}"
fi

"${ROOT[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update
readonly -a DOCKER_PACKAGES=(
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
)
"${ROOT[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${DOCKER_PACKAGES[@]}"
"${ROOT[@]}" systemctl enable --now docker

if [[ "${TARGET_USER}" != "root" ]]; then
  "${ROOT[@]}" usermod -aG docker "${TARGET_USER}"
fi

case "$(uname -m)" in
  x86_64)
    readonly CLIENT_ARCH="amd64"
    ;;
  aarch64 | arm64)
    readonly CLIENT_ARCH="arm64"
    ;;
  *)
    echo "ERROR: unsupported CPU architecture '$(uname -m)'." >&2
    exit 1
    ;;
esac

readonly KUBECTL_VERSION="$(
  curl --proto '=https' --tlsv1.2 -fsSL https://dl.k8s.io/release/stable.txt
)"
if [[ ! "${KUBECTL_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: received invalid kubectl release '${KUBECTL_VERSION}'." >&2
  exit 1
fi

echo "Installing kubectl ${KUBECTL_VERSION}..."
readonly KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${CLIENT_ARCH}/kubectl"
curl --proto '=https' --tlsv1.2 -fsSLo "${TEMP_DIR}/kubectl" "${KUBECTL_URL}"
curl --proto '=https' --tlsv1.2 -fsSLo "${TEMP_DIR}/kubectl.sha256" "${KUBECTL_URL}.sha256"
readonly KUBECTL_CHECKSUM="$(<"${TEMP_DIR}/kubectl.sha256")"
printf '%s  %s\n' "${KUBECTL_CHECKSUM}" "${TEMP_DIR}/kubectl" |
  sha256sum --check
"${ROOT[@]}" install -o root -g root -m 0755 "${TEMP_DIR}/kubectl" /usr/local/bin/kubectl

echo "Installing the latest stable k3d..."
curl --proto '=https' --tlsv1.2 -fsSLo "${TEMP_DIR}/install-k3d.sh" https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh
chmod 0700 "${TEMP_DIR}/install-k3d.sh"
declare -a k3d_environment=(
  USE_SUDO=false
  K3D_INSTALL_DIR=/usr/local/bin
)
if [[ -n "${IOT_K3D_VERSION:-}" ]]; then
  k3d_environment+=("TAG=${IOT_K3D_VERSION}")
fi
"${ROOT[@]}" env "${k3d_environment[@]}" bash "${TEMP_DIR}/install-k3d.sh" --no-sudo

echo "Installing the latest stable Helm 3..."
curl --proto '=https' --tlsv1.2 -fsSLo "${TEMP_DIR}/install-helm.sh" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 0700 "${TEMP_DIR}/install-helm.sh"
declare -a helm_arguments=(--no-sudo)
if [[ -n "${IOT_HELM_VERSION:-}" ]]; then
  helm_arguments+=(--version "${IOT_HELM_VERSION}")
fi
"${ROOT[@]}" env USE_SUDO=false HELM_INSTALL_DIR=/usr/local/bin bash "${TEMP_DIR}/install-helm.sh" "${helm_arguments[@]}"

echo
echo "Installed versions:"
docker --version
docker compose version
kubectl version --client
k3d version
helm version --short
git --version
jq --version

"${ROOT[@]}" docker info >/dev/null

echo
echo "All bonus VM tools are installed and the Docker daemon is running."
if [[ "${TARGET_USER}" != "root" ]] &&
  ! id -Gn | tr ' ' '\n' | grep -Fqx docker; then
  echo "Docker group membership was added for '${TARGET_USER}'."
  echo "Run 'newgrp docker' once before running bonus/scripts/setup.sh in this shell."
else
  echo "Docker is available to the current shell."
fi
