#!/usr/bin/env bash
set -Eeux -o pipefail

IOT_TARGET_USER=vagrant bash /workspace/p3/scripts/install-tools.sh

if [[ ! -f /swapfile ]]; then
  fallocate -l 4G /swapfile
  chmod 0600 /swapfile
  mkswap /swapfile
fi
if ! swapon --show=NAME --noheadings | grep -Fxq /swapfile; then
  swapon /swapfile
fi
grep -Fqx '/swapfile none swap sw 0 0' /etc/fstab || \
  printf '%s\n' '/swapfile none swap sw 0 0' >> /etc/fstab

echo "Bonus VM tools are installed. Run 'vagrant reload', then execute:"
echo "  vagrant ssh -c 'cd /workspace && bash bonus/scripts/setup.sh'"
