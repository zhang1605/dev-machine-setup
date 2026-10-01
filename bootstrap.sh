#!/usr/bin/env bash
# dev-machine-setup - the real installer.
#
#   bash bootstrap.sh                       interactive
#   bash bootstrap.sh --yes                 accept all defaults
#   bash bootstrap.sh --only=mise,shell     re-run just those modules
#
set -uo pipefail

DMS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
declare -a WARNINGS=()

# shellcheck source=lib/common.sh
source "$DMS_ROOT/lib/common.sh"

ALL_MODULES=(pkgs mise omz atuin brew tmux nvim ai git shell)

usage() {
  cat >&2 <<USAGE
${C_BOLD}dev-machine-setup${C_RESET}

  bash bootstrap.sh [options]

Options
  -y, --yes                Non-interactive; take every default.
      --only=A,B           Run only these modules.
      --skip=A,B           Run everything except these modules.
      --mise-extras=A,B    Optional mise tools (empty for none).
                           Choices: terraform terragrunt changie duckdb snowflake
      --ai=A,B             AI CLIs (empty for none).
                           Choices: claude codex herdr pi metaai
      --email=X            navex | personal | any@address
      --name="X"           git user.name
      --theme=X            oh-my-zsh theme (default: bira)
      --list-modules       Print module names and exit.
  -h, --help               This.

Modules: ${ALL_MODULES[*]}
USAGE
}

# ------------------------------------------------------------------ arguments
NONINTERACTIVE=0
ONLY=""
SKIP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)         NONINTERACTIVE=1 ;;
    --only=*)         ONLY="${1#*=}" ;;
    --skip=*)         SKIP="${1#*=}" ;;
    --mise-extras=*)  MISE_EXTRAS_ARG="${1#*=}" ;;
    --ai=*)           AI_TOOLS_ARG="${1#*=}" ;;
    --email=*)        GIT_EMAIL_ARG="${1#*=}" ;;
    --name=*)         DMS_GIT_NAME="${1#*=}" ;;
    --theme=*)        DMS_ZSH_THEME="${1#*=}" ;;
    --list-modules)   printf '%s\n' "${ALL_MODULES[@]}"; exit 0 ;;
    -h|--help)        usage; exit 0 ;;
    *)                printf 'Unknown option: %s\n\n' "$1" >&2; usage; exit 2 ;;
  esac
  shift
done

# shellcheck source=lib/pkgs.sh
source "$DMS_ROOT/lib/pkgs.sh"
# shellcheck source=lib/mise.sh
source "$DMS_ROOT/lib/mise.sh"
# shellcheck source=lib/shell.sh
source "$DMS_ROOT/lib/shell.sh"
# shellcheck source=lib/extras.sh
source "$DMS_ROOT/lib/extras.sh"
# shellcheck source=lib/ai.sh
source "$DMS_ROOT/lib/ai.sh"
# shellcheck source=lib/git.sh
source "$DMS_ROOT/lib/git.sh"

_in_csv() { [[ ",$1," == *",$2,"* ]]; }
enabled() {
  local m="$1"
  [[ -n $ONLY ]] && { _in_csv "$ONLY" "$m"; return; }
  [[ -n $SKIP ]] && { _in_csv "$SKIP" "$m" && return 1; }
  return 0
}

# ----------------------------------------------------------------- preflight
detect_os
setup_sudo

printf '\n%s\n' "${C_BOLD}${C_CYAN}dev-machine-setup${C_RESET}" >&2
log "os        : $OS_NAME  (pkg: $PKG)"
log "user      : $(id -un)$( [[ ${IS_ROOT} -eq 1 ]] && printf ' (root)')"
log "repo      : $DMS_ROOT"
log "mode      : $( interactive && printf 'interactive' || printf 'non-interactive (defaults)' )"
[[ -n $ONLY ]] && log "only      : $ONLY"
[[ -n $SKIP ]] && log "skip      : $SKIP"

if [[ $TTY_OK -eq 0 && $NONINTERACTIVE -eq 0 ]]; then
  warn "no tty available - falling back to defaults for every prompt"
fi

# -------------------------------------------- collect every choice up front
# The install takes many minutes; ask everything now so it can run unattended.
MISE_EXTRAS=()
AI_TOOLS=()
GIT_EMAIL="$GIT_EMAIL_WORK"

enabled mise && choose_mise_extras
enabled ai   && choose_ai_tools
enabled git  && choose_git_identity

if interactive; then
  printf '\n' >&2
  log "mise extras : ${MISE_EXTRAS[*]:-none}"
  log "ai clis     : ${AI_TOOLS[*]:-none}"
  log "git email   : $GIT_EMAIL"
  ui_confirm "Proceed?" y || die "Aborted."
fi

# Make `dev-machine` available on PATH regardless of which modules run.
mkdir -p "$HOME/.local/bin"
ln -sfn "$DMS_ROOT/bin/dev-machine" "$HOME/.local/bin/dev-machine"

START=$(date +%s)

# ------------------------------------------------------------------- execute
enabled pkgs  && install_packages
enabled mise  && { install_mise && write_mise_config && install_mise_tools; }
enabled omz   && install_omz
enabled atuin && install_atuin
enabled brew  && install_homebrew
enabled tmux  && install_tmux_conf
enabled nvim  && install_lazyvim
enabled ai    && install_ai_tools
enabled git   && configure_git
# Last: atuin/brew may have touched the rc files, and our block wins.
enabled shell && { configure_shells; set_zsh_theme; set_default_shell; }

# ------------------------------------------------------------------- summary
ELAPSED=$(( $(date +%s) - START ))
printf '\n%s\n' "${C_GREEN}${C_BOLD}Done${C_RESET} ${C_DIM}in $((ELAPSED / 60))m $((ELAPSED % 60))s${C_RESET}" >&2

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  printf '\n%s\n' "${C_YELLOW}${#WARNINGS[@]} warning(s):${C_RESET}" >&2
  printf '  %s\n' "${WARNINGS[@]}" >&2
fi

cat >&2 <<NEXT

${C_BOLD}Next${C_RESET}
  exec zsh -l              start a fresh login shell (or log out and back in)
  mise ls                  what mise installed
  nvim                     first launch bootstraps LazyVim plugins
  atuin register / login   sync shell history (optional)
  tmux                     prefix is C-a / C-b, config in ~/.tmux.conf.local

${C_BOLD}Re-run later${C_RESET}
  dev-machine update                  git pull + full re-run
  dev-machine run --only=mise         just refresh mise tools
NEXT
