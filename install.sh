#!/bin/sh
# dev-machine-config bootstrap
#
#   curl -fsSL https://herdr.dev/install.sh | sh
#   curl -fsSL https://herdr.dev/install.sh | sh -s -- --yes
#
# Tiny POSIX bootstrap: make sure git/curl exist, clone the repo, hand off to
# bootstrap.sh (bash). Everything interesting lives in the repo.

set -eu

REPO="${DMC_REPO:-https://github.com/MichaelZhang-Navex/dev-machine-config.git}"
BRANCH="${DMC_BRANCH:-main}"
DIR="${DMC_DIR:-$HOME/.dev-machine-config}"

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

if [ "$(id -u)" = "0" ]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
  say "Caching sudo credentials"
  if [ -r /dev/tty ]; then sudo -v </dev/tty; else sudo -v; fi
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
if [ -d "$DIR/.git" ]; then
  say "Updating $DIR"
  git -C "$DIR" fetch --quiet origin "$BRANCH" || warn "fetch failed; using local copy"
  git -C "$DIR" checkout --quiet "$BRANCH" 2>/dev/null || true
  git -C "$DIR" reset --hard --quiet "origin/$BRANCH" 2>/dev/null || warn "could not fast-forward; using local copy"
elif [ -d "$DIR" ] && [ -f "$DIR/bootstrap.sh" ]; then
  say "Using existing checkout at $DIR"
else
  [ -e "$DIR" ] && die "$DIR exists but is not a dev-machine-config checkout. Move it aside or set DMC_DIR."
  say "Cloning $REPO -> $DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$DIR"
fi

[ -f "$DIR/bootstrap.sh" ] || die "$DIR/bootstrap.sh missing after clone."
chmod +x "$DIR/bootstrap.sh" "$DIR"/bin/* 2>/dev/null || true

exec bash "$DIR/bootstrap.sh" "$@"
