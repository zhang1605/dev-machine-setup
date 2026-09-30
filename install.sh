#!/bin/sh
# dev-machine-setup bootstrap
#
#   curl -fsSL https://raw.githubusercontent.com/zhang1605/dev-machine-setup/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/zhang1605/dev-machine-setup/main/install.sh | sh -s -- --yes
#
# Tiny POSIX bootstrap: make sure git/curl exist, clone the repo, hand off to
# bootstrap.sh (bash). Everything interesting lives in the repo.

set -eu

REPO="${DMS_REPO:-https://github.com/zhang1605/dev-machine-setup.git}"
BRANCH="${DMS_BRANCH:-main}"
DIR="${DMS_DIR:-$HOME/.dev-machine-setup}"

say()  { printf '\033[34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m  x\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] || die "This installer targets Linux (Ubuntu/Debian or Arch). Detected: $(uname -s)"
[ -r /etc/os-release ] || die "/etc/os-release not found; cannot detect distribution."

# shellcheck disable=SC1091
. /etc/os-release
ID="${ID:-unknown}"
ID_LIKE="${ID_LIKE:-}"

case "$ID" in
  ubuntu|debian|pop|linuxmint|elementary|zorin) PKG=apt ;;
  arch|archarm|manjaro|endeavouros|garuda)      PKG=pacman ;;
  *)
    case " $ID_LIKE " in
      *debian*|*ubuntu*) PKG=apt ;;
      *arch*)            PKG=pacman ;;
      *) die "Unsupported distribution: $ID. Supported: Ubuntu/Debian and Arch." ;;
    esac
    ;;
esac

# Can we actually OPEN the terminal? `[ -r /dev/tty ]` only checks permission
# bits: with no controlling terminal the node is readable but opening it fails
# with ENXIO, and a failed redirection under `set -e` takes the script with it.
# The subshell contains that failure - `:` is a POSIX special builtin, so a
# redirection error on it is fatal to a non-interactive shell.
tty_ok() { ( : </dev/tty ) 2>/dev/null; }

if [ "$(id -u)" = "0" ]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
  say "Caching sudo credentials"
  if tty_ok; then
    sudo -v </dev/tty || die "sudo authentication failed."
  elif ! sudo -v; then
    die "sudo wants a password and there is no terminal to ask on. Either run 'sudo -v' first, or re-run attached to a tty."
  fi
else
  die "Run as root or install sudo first."
fi

# --- minimal prerequisites: git, curl, bash ---------------------------------
need_boot=""
for c in git curl bash; do
  command -v "$c" >/dev/null 2>&1 || need_boot="$need_boot $c"
done

if [ -n "$need_boot" ]; then
  say "Installing bootstrap prerequisites:$need_boot"
  case "$PKG" in
    apt)
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -qq
      # shellcheck disable=SC2086
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq ca-certificates $need_boot
      ;;
    pacman)
      # shellcheck disable=SC2086
      $SUDO pacman -Sy --needed --noconfirm ca-certificates $need_boot
      ;;
  esac
fi

# --- fetch the repo ----------------------------------------------------------
# Adopt a checkout from when this project was called dev-machine-config, so a
# box provisioned then does not end up with two of them.
LEGACY_DIR="$HOME/.dev-machine-config"
if [ -d "$LEGACY_DIR" ] && [ ! -e "$DIR" ]; then
  say "Renaming $LEGACY_DIR -> $DIR"
  mv "$LEGACY_DIR" "$DIR"
fi

if [ -d "$DIR/.git" ]; then
  say "Updating $DIR"
  git -C "$DIR" remote set-url origin "$REPO" 2>/dev/null || true
  git -C "$DIR" fetch --quiet origin "$BRANCH" || warn "fetch failed; using local copy"
  git -C "$DIR" checkout --quiet "$BRANCH" 2>/dev/null || true
  git -C "$DIR" reset --hard --quiet "origin/$BRANCH" 2>/dev/null || warn "could not fast-forward; using local copy"
elif [ -d "$DIR" ] && [ -f "$DIR/bootstrap.sh" ]; then
  say "Using existing checkout at $DIR"
else
  [ -e "$DIR" ] && die "$DIR exists but is not a dev-machine-setup checkout. Move it aside or set DMS_DIR."
  say "Cloning $REPO -> $DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$DIR"
fi

[ -f "$DIR/bootstrap.sh" ] || die "$DIR/bootstrap.sh missing after clone."
chmod +x "$DIR/bootstrap.sh" "$DIR"/bin/* 2>/dev/null || true

exec bash "$DIR/bootstrap.sh" "$@"
