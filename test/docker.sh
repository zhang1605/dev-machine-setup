#!/usr/bin/env bash
# End-to-end smoke test in throwaway containers.
#
#   bash test/docker.sh            # ubuntu + arch
#   bash test/docker.sh ubuntu     # one distro
#
# Runs the real installer non-interactively as an unprivileged sudo user, then
# runs test/verify.sh. Expect 10-20 min per image and a lot of network traffic.
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$#" -gt 0 ]; then TARGETS=("$@"); else TARGETS=(ubuntu arch); fi
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }

image_for() {
  case "$1" in
    ubuntu) echo "ubuntu:24.04" ;;
    arch)   echo "archlinux:base-devel" ;;
    *)      return 1 ;;
  esac
}

prep_for() {
  case "$1" in
    ubuntu) echo 'apt-get update -qq && apt-get install -y -qq sudo git curl ca-certificates >/dev/null' ;;
    arch)   echo 'pacman -Sy --noconfirm --needed sudo git curl >/dev/null' ;;
  esac
}

status=0
for target in "${TARGETS[@]}"; do
  if ! image="$(image_for "$target")"; then
    echo "unknown target: $target (expected ubuntu or arch)" >&2
    status=1; continue
  fi
  printf '\n==============================================================\n'
  printf '  %s  (%s)\n' "$target" "$image"
  printf '==============================================================\n'

  docker run --rm -v "$ROOT:/src:ro" "$image" bash -c "
    set -e
    $(prep_for "$target")
    useradd -m -s /bin/bash dev
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
    cp -r /src /home/dev/.dev-machine-config
    chown -R dev:dev /home/dev/.dev-machine-config
    su - dev -c 'bash ~/.dev-machine-config/bootstrap.sh --yes --ai= --email=navex'
    su - dev -c 'bash ~/.dev-machine-config/test/verify.sh'
  " || { echo "  >>> $target FAILED"; status=1; }
done

exit "$status"
