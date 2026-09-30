#!/usr/bin/env bash
# End-to-end smoke test in throwaway containers.
#
#   bash test/docker.sh                  # ubuntu + arch, both as linux/amd64
#   bash test/docker.sh ubuntu           # one target
#   bash test/docker.sh ubuntu-arm       # native arm64, fast iteration
#   DMC_PLATFORM=linux/arm64 bash test/docker.sh ubuntu
#
# Runs the real installer non-interactively as an unprivileged sudo user, then
# runs test/verify.sh. Expect 10-20 min per image and a lot of network traffic;
# emulated (non-native) platforms are slower still.
#
# Targets default to linux/amd64 because that is what real Ubuntu/Arch boxes
# almost always are, and because the official `archlinux` image is amd64-only.
# The *-arm targets run native on Apple Silicon for a quicker loop, but note
# they exercise different binaries: Arch Linux ARM is a separate distro with
# its own mirrors, and Homebrew ships no bottles for ARM Linux, so anything
# you `brew install` there compiles from source.
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$#" -gt 0 ]; then TARGETS=("$@"); else TARGETS=(ubuntu arch); fi
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running" >&2; exit 1; }

# target -> "image platform"
spec_for() {
  case "$1" in
    ubuntu)     echo "ubuntu:24.04                   linux/amd64" ;;
    arch)       echo "archlinux:base-devel           linux/amd64" ;;
    ubuntu-arm) echo "ubuntu:24.04                   linux/arm64" ;;
    arch-arm)   echo "menci/archlinuxarm:base-devel  linux/arm64" ;;
    *)          return 1 ;;
  esac
}

prep_for() {
  case "$1" in
    ubuntu*) echo 'apt-get update -qq && apt-get install -y -qq sudo git curl ca-certificates >/dev/null' ;;
    arch*)   echo 'pacman-key --init >/dev/null 2>&1 || true
                   pacman -Sy --noconfirm --needed sudo git curl >/dev/null' ;;
  esac
}

HOST_PLATFORM="linux/$(docker version --format '{{.Server.Arch}}' 2>/dev/null || echo amd64)"

status=0
for target in "${TARGETS[@]}"; do
  if ! spec="$(spec_for "$target")"; then
    echo "unknown target: $target (expected ubuntu, arch, ubuntu-arm, arch-arm)" >&2
    status=1; continue
  fi
  read -r image platform <<<"$spec"
  platform="${DMC_PLATFORM:-$platform}"

  printf '\n==============================================================\n'
  printf '  %s  (%s, %s%s)\n' "$target" "$image" "$platform" \
    "$([ "$platform" = "$HOST_PLATFORM" ] && printf ' native' || printf ' emulated - slow')"
  printf '==============================================================\n'

  docker run --rm --platform "$platform" -v "$ROOT:/src:ro" "$image" bash -c "
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
