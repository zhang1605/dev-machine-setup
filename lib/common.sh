#!/usr/bin/env bash
# Shared helpers: logging, distro detection, sudo, idempotent file blocks,
# and a small interactive checkbox/radio UI that works under `curl | sh`.
# shellcheck shell=bash

# ---------------------------------------------------------------- tty & colors
# Under `curl ... | sh` stdin is the pipe, so all prompting goes through
# /dev/tty on fd 3 (read) and fd 4 (draw).
# Probe /dev/tty in a subshell first, and note that `[ -r /dev/tty ]` is not the
# test you want: it checks permission bits, but with no controlling terminal the
# node is readable and opening it still fails with ENXIO. The subshell also
# keeps a failed `exec` from leaving this shell's descriptors half-applied.
if ( : </dev/tty ) 2>/dev/null && ( : >/dev/tty ) 2>/dev/null; then
  exec 3</dev/tty 4>/dev/tty
  TTY_OK=1
else
  exec 3<&0 4>&2
  TTY_OK=0
fi

if [[ -z ${NO_COLOR:-} && ( $TTY_OK == 1 || -t 2 ) ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET= C_BOLD= C_DIM= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_CYAN=
fi

# ------------------------------------------------------------------- logging
step()  { printf '\n%s %s\n' "${C_BLUE}==>${C_RESET}" "${C_BOLD}$*${C_RESET}" >&2; }
log()   { printf '    %s\n' "${C_DIM}$*${C_RESET}" >&2; }
ok()    { printf '  %s %s\n' "${C_GREEN}✓${C_RESET}" "$*" >&2; }
skip()  { printf '  %s %s\n' "${C_DIM}·${C_RESET}" "${C_DIM}$*${C_RESET}" >&2; }
warn()  { printf '  %s %s\n' "${C_YELLOW}!${C_RESET}" "$*" >&2; WARNINGS+=("$*"); }
die()   { printf '  %s %s\n' "${C_RED}✗${C_RESET}" "$*" >&2; exit 1; }

have()  { command -v "$1" >/dev/null 2>&1; }

# Run a step, but don't abort the whole install if it fails.
try() {
  local what="$1"; shift
  if "$@"; then return 0; fi
  warn "$what failed (continuing)"
  return 1
}

# Portable `mapfile -t` replacement (works on bash 3.2 too).
read_lines() {
  local __name="$1" __line
  eval "$__name=()"
  while IFS= read -r __line; do
    [[ -n $__line ]] || continue
    eval "$__name+=(\"\$__line\")"
  done
  return 0
}

# ------------------------------------------------------------- os detection
detect_os() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_NAME="${PRETTY_NAME:-$OS_ID}"
  local like=" ${ID_LIKE:-} "
  case "$OS_ID" in
    ubuntu|debian|pop|linuxmint|elementary|zorin) PKG=apt ;;
    arch|archarm|manjaro|endeavouros|garuda)      PKG=pacman ;;
    *)
      case "$like" in
        *debian*|*ubuntu*) PKG=apt ;;
        *arch*)            PKG=pacman ;;
        *) die "Unsupported distribution: $OS_ID" ;;
      esac
      ;;
  esac
}

setup_sudo() {
  if [[ $(id -u) -eq 0 ]]; then
    SUDO=""; IS_ROOT=1
  elif have sudo; then
    SUDO="sudo"; IS_ROOT=0
    sudo -v <&3 || die "sudo authentication failed."
  else
    die "Run as root or install sudo."
  fi
}

# Run a command as the target (non-root) user. Installers such as Homebrew and
# makepkg refuse to run as root.
as_user() {
  if [[ ${IS_ROOT:-0} -eq 1 ]]; then
    return 1   # caller decides how to handle
  fi
  "$@"
}

# ------------------------------------------------------- managed file blocks
# Replace (or append) a marker-delimited block in a file. Idempotent.
BLOCK_BEGIN='# >>> dev-machine-config >>>'
BLOCK_END='# <<< dev-machine-config <<<'

write_block() {
  local file="$1" body="$2" tmp
  mkdir -p "$(dirname "$file")"
  [[ -f $file ]] || : >"$file"
  tmp="$(mktemp)"
  awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
    $0 == b { inblock = 1; next }
    $0 == e { inblock = 0; next }
    !inblock { print }
  ' "$file" >"$tmp"
  # collapse trailing blank lines, then append a fresh block
  awk 'BEGIN{n=0} {lines[NR]=$0} END{ last=NR; while (last>0 && lines[last]=="") last--; for(i=1;i<=last;i++) print lines[i] }' "$tmp" >"$tmp.2"
  {
    cat "$tmp.2"
    [[ -s $tmp.2 ]] && printf '\n'
    printf '%s\n' "$BLOCK_BEGIN"
    printf '%s\n' "$body"
    printf '%s\n' "$BLOCK_END"
  } >"$file"
  rm -f "$tmp" "$tmp.2"
}

backup_path() {
  local p="$1"
  [[ -e $p || -L $p ]] || return 0
  local dest="${p}.dmc-backup.$(date +%Y%m%d%H%M%S)"
  mv "$p" "$dest"
  warn "moved existing $p -> $dest"
}

# --------------------------------------------------------------- interactive
interactive() { [[ ${NONINTERACTIVE:-0} -eq 0 && ${TTY_OK:-0} -eq 1 ]]; }

_tty_cleanup() { [[ ${TTY_OK:-0} -eq 1 ]] && printf '\033[?25h' >&4; }

# ui_multiselect "Title" "key|Label|on" "key2|Label2|off" ...
# Selected keys are printed to stdout, one per line.
ui_multiselect() {
  local title="$1"; shift
  local -a keys=() labels=() state=()
  local item k l d
  for item in "$@"; do
    IFS='|' read -r k l d <<<"$item"
    keys+=("$k"); labels+=("$l")
    [[ $d == "on" ]] && state+=(1) || state+=(0)
  done
  local n=${#keys[@]} i

  if ! interactive; then
    for ((i = 0; i < n; i++)); do ((state[i])) && printf '%s\n' "${keys[i]}"; done
    return 0
  fi

  local cur=0 key key2 first=1
  printf '\n  %s\n' "${C_BOLD}${title}${C_RESET}" >&4
  printf '  %s\n\n' "${C_DIM}↑/↓ or j/k move · space toggle · a all · n none · enter confirm${C_RESET}" >&4
  printf '\033[?25l' >&4
  trap _tty_cleanup EXIT

  while true; do
    if ((first)); then first=0; else printf '\033[%dA' "$n" >&4; fi
    for ((i = 0; i < n; i++)); do
      local mark=" " pointer="   " color="${C_DIM}"
      ((state[i])) && { mark="x"; color=""; }
      ((i == cur)) && pointer=" ${C_CYAN}▸${C_RESET} "
      printf '\033[2K%s[%s] %s%s%s\n' "$pointer" "$mark" "$color" "${labels[i]}" "${C_RESET}" >&4
    done
    IFS= read -rsn1 -u 3 key || break
    case "$key" in
      $'\033')
        read -rsn2 -t 0.05 -u 3 key2 || true
        case "$key2" in
          '[A') ((cur = (cur - 1 + n) % n)) ;;
          '[B') ((cur = (cur + 1) % n)) ;;
        esac
        ;;
      ' ')  state[cur]=$((1 - state[cur])) ;;
      k|K)  ((cur = (cur - 1 + n) % n)) ;;
      j|J)  ((cur = (cur + 1) % n)) ;;
      a|A)  for ((i = 0; i < n; i++)); do state[i]=1; done ;;
      n|N)  for ((i = 0; i < n; i++)); do state[i]=0; done ;;
      q|Q)  printf '\033[?25h\n' >&4; trap - EXIT; die "Aborted." ;;
      '')   break ;;
    esac
  done

  printf '\033[?25h\n' >&4
  trap - EXIT
  for ((i = 0; i < n; i++)); do ((state[i])) && printf '%s\n' "${keys[i]}"; done
}

# ui_select "Title" "key|Label" ... -> prints one key
ui_select() {
  local title="$1"; shift
  local -a keys=() labels=()
  local item k l
  for item in "$@"; do
    IFS='|' read -r k l <<<"$item"
    keys+=("$k"); labels+=("$l")
  done
  local n=${#keys[@]} i

  if ! interactive; then printf '%s\n' "${keys[0]}"; return 0; fi

  local cur=0 key key2 first=1
  printf '\n  %s\n' "${C_BOLD}${title}${C_RESET}" >&4
  printf '  %s\n\n' "${C_DIM}↑/↓ or j/k move · enter confirm${C_RESET}" >&4
  printf '\033[?25l' >&4
  trap _tty_cleanup EXIT

  while true; do
    if ((first)); then first=0; else printf '\033[%dA' "$n" >&4; fi
    for ((i = 0; i < n; i++)); do
      local mark=" " pointer="   " color="${C_DIM}"
      ((i == cur)) && { mark="•"; pointer=" ${C_CYAN}▸${C_RESET} "; color=""; }
      printf '\033[2K%s(%s) %s%s%s\n' "$pointer" "$mark" "$color" "${labels[i]}" "${C_RESET}" >&4
    done
    IFS= read -rsn1 -u 3 key || break
    case "$key" in
      $'\033') read -rsn2 -t 0.05 -u 3 key2 || true
               case "$key2" in '[A') ((cur = (cur - 1 + n) % n));; '[B') ((cur = (cur + 1) % n));; esac ;;
      k|K) ((cur = (cur - 1 + n) % n)) ;;
      j|J) ((cur = (cur + 1) % n)) ;;
      q|Q) printf '\033[?25h\n' >&4; trap - EXIT; die "Aborted." ;;
      '')  break ;;
    esac
  done

  printf '\033[?25h\n' >&4
  trap - EXIT
  printf '%s\n' "${keys[cur]}"
}

# ui_ask "Prompt" "default" -> prints the answer
ui_ask() {
  local prompt="$1" default="${2:-}" answer
  if ! interactive; then printf '%s\n' "$default"; return 0; fi
  printf '  %s ' "${C_BOLD}${prompt}${C_RESET}${default:+ ${C_DIM}[$default]${C_RESET}}" >&4
  IFS= read -r -u 3 answer || answer=""
  printf '%s\n' "${answer:-$default}"
}

# ui_confirm "Prompt" [default_yes]
ui_confirm() {
  local prompt="$1" def="${2:-y}" answer
  if ! interactive; then [[ $def == y ]]; return; fi
  printf '  %s %s ' "${C_BOLD}${prompt}${C_RESET}" "${C_DIM}[$( [[ $def == y ]] && echo 'Y/n' || echo 'y/N')]${C_RESET}" >&4
  IFS= read -r -u 3 answer || answer=""
  answer="${answer:-$def}"
  case "$answer" in [yY]*) return 0 ;; *) return 1 ;; esac
}
