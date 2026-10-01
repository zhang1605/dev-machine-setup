#!/usr/bin/env bash
# System packages: apt (Ubuntu/Debian) or pacman + yay (Arch).
# shellcheck shell=bash

# Shared toolchain + the build deps mise/Homebrew/python want available.
APT_PACKAGES=(
  build-essential ca-certificates curl wget file git gnupg pkg-config
  zsh vim tmux
  fzf ripgrep fd-find jq tree htop less man-db procps rsync openssh-client
  unzip zip tar gzip xz-utils bzip2
  wslu wl-clipboard xclip
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev
  libncurses-dev libffi-dev liblzma-dev tk-dev uuid-dev
  python3 python3-venv
)

PACMAN_PACKAGES=(
  base-devel ca-certificates curl wget file git gnupg pkgconf
  zsh vim tmux
  fzf ripgrep fd jq tree htop less man-db procps-ng rsync openssh
  unzip zip tar gzip xz bzip2
  wl-clipboard xclip
  openssl zlib readline sqlite ncurses libffi tk
  python
)

install_packages() {
  step "System packages (${OS_NAME})"
  case "$PKG" in
    apt)    _apt_install ;;
    pacman) _pacman_install ;;
  esac
}

_apt_install() {
  log "apt-get update"
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
  log "installing ${#APT_PACKAGES[@]} packages (this takes a minute)"
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq \
    -o Dpkg::Use-Pty=0 "${APT_PACKAGES[@]}" \
    || die "apt-get install failed; see the error above"
  ok "apt packages installed"

  # Debian/Ubuntu ship fd as `fdfind` to avoid a name clash.
  if have fdfind && ! have fd; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    ok "linked fdfind -> ~/.local/bin/fd"
  fi
  if have batcat && ! have bat; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
}

_pacman_install() {
  log "pacman -Syu (full sync; partial upgrades are unsupported on Arch)"
  $SUDO pacman -Syu --needed --noconfirm "${PACMAN_PACKAGES[@]}" \
    || die "pacman install failed; see the error above"
  ok "pacman packages installed"
  _install_yay
  _install_wslu_aur
}

# wslu is AUR-only on Arch (one missing target aborts the whole pacman
# transaction), and it is only useful inside WSL.
_install_wslu_aur() {
  is_wsl || return 0
  if have wslview; then skip "wslu already installed"; return 0; fi
  have yay || { warn "no yay; install wslu from the AUR for wslview"; return 0; }
  yay -S --needed --noconfirm wslu <&3 && ok "wslu installed (AUR)" \
    || warn "wslu AUR install failed"
}

_install_yay() {
  if have yay; then skip "yay already installed"; return 0; fi
  if have paru; then skip "paru present; skipping yay"; return 0; fi
  if [[ ${IS_ROOT:-0} -eq 1 ]]; then
    warn "running as root: makepkg refuses to build as root, skipping yay"
    return 0
  fi

  step "yay (AUR helper)"
  local build
  build="$(mktemp -d)"
  (
    cd "$build"
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
  ) <&3 && ok "yay installed" || warn "yay build failed"
  rm -rf "$build"
}
