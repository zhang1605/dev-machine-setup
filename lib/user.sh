#!/usr/bin/env bash
# Non-root user bootstrap. Arch (notably ArchWSL) often starts life as root
# with no "create a user" step, unlike Ubuntu WSL - and several installers
# refuse to run as root (makepkg/yay, Homebrew). So when this installer runs
# as root it creates a real user (default: michael), gives it passwordless
# sudo, moves the checkout where the user can own it, and re-execs itself as
# that user. Everything after this runs natively as the user with a correct
# $HOME. Non-root runs are untouched.
# shellcheck shell=bash

DMS_DEFAULT_USER="michael"
# Set by --user=NAME. Empty means "prompt interactively, default michael".
DMS_USER_ARG="${DMS_USER_ARG:-}"

choose_dev_user() {
  local def="${DMS_USER_ARG:-$DMS_DEFAULT_USER}"
  if [[ -n ${DMS_USER_ARG:-} ]]; then
    TARGET_USER="$DMS_USER_ARG"
  else
    TARGET_USER="$(ui_ask 'Linux username to create/use:' "$def")"
  fi
  # Keep it a valid portable username: lowercase, digits, _ and -.
  TARGET_USER="$(printf '%s' "$TARGET_USER" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
  [[ -n $TARGET_USER ]] || TARGET_USER="$def"
}

_install_sudo_if_missing() {
  have sudo && return 0
  log "installing sudo (needed for the $TARGET_USER account)"
  case "$PKG" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update -qq \
           && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo ;;
    pacman) pacman -Sy --needed --noconfirm sudo ;;
  esac
}

ensure_dev_user() {
  [[ ${IS_ROOT:-0} -eq 1 ]] || return 0

  choose_dev_user
  step "User account ($TARGET_USER)"

  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    log "creating user $TARGET_USER"
    useradd -m -s /bin/bash "$TARGET_USER" \
      || die "useradd failed for $TARGET_USER"
    ok "created $TARGET_USER"
  else
    log "$TARGET_USER already exists"
  fi

  _install_sudo_if_missing || warn "could not install sudo; continuing anyway"

  # Passwordless sudo keeps the re-exec below (and later re-runs) working
  # without another password prompt. The login password is separate.
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$TARGET_USER" >"/etc/sudoers.d/$TARGET_USER"
  chmod 0440 "/etc/sudoers.d/$TARGET_USER"
  ok "sudoers entry for $TARGET_USER"

  if interactive; then
    log "set a password for $TARGET_USER (used for login / su)"
    if passwd "$TARGET_USER" <&3; then
      ok "password set"
    else
      warn "passwd failed; login password unchanged (sudo still works)"
    fi
  else
    log "non-interactive: leaving the login password unset (sudo works)"
  fi

  # Relocate the checkout into the user's home so `dev-machine update`
  # (which defaults to ~/.dev-machine-setup) keeps working after this.
  local target_home new_dir
  target_home="$(eval echo "~$TARGET_USER")"
  new_dir="$target_home/.dev-machine-setup"
  if [[ $DMS_ROOT != "$new_dir" ]]; then
    log "moving $DMS_ROOT -> $new_dir"
    mkdir -p "$target_home"
    rm -rf "$new_dir"
    cp -a "$DMS_ROOT/." "$new_dir/" || die "could not copy checkout to $new_dir"
    DMS_ROOT="$new_dir"
  fi
  chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$DMS_ROOT"
  chmod +x "$DMS_ROOT/bootstrap.sh" "$DMS_ROOT"/bin/* 2>/dev/null || true

  log "re-executing as $TARGET_USER"
  # Forward the original arguments unchanged (--user= is harmless to keep:
  # a non-root run ignores it). A login shell gives the user a correct
  # $HOME; DMS_DIR is carried inside the command because `su -` scrubs env.
  local qroot qargs
  qroot="$(printf '%s' "$DMS_ROOT" | sed "s/'/'\\\\''/g")"
  qargs="${DMS_ORIG_ARGS_Q:-}"
  # shellcheck disable=SC2086
  exec su - "$TARGET_USER" -c \
    "DMS_DIR='$qroot' bash '$qroot/bootstrap.sh' $qargs"
}
