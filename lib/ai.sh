#!/usr/bin/env bash
# AI coding CLIs - all opt-in via multi-select.
# shellcheck shell=bash

# key|label|default
AI_MENU=(
  "claude|Claude Code        ${C_DIM}claude.ai/install.sh${C_RESET}|on"
  "codex|Codex CLI          ${C_DIM}chatgpt.com/codex/install.sh${C_RESET}|off"
  "herdr|herdr              ${C_DIM}herdr.dev/install.sh${C_RESET}|on"
  "pi|pi                 ${C_DIM}pi.dev/install.sh${C_RESET}|off"
  "metaai|Meta AI dev CLI    ${C_DIM}dev.meta.ai/install.sh${C_RESET}|off"
)

_ai_install_one() {
  case "$1" in
    claude) curl -fsSL https://claude.ai/install.sh | bash ;;
    codex)  curl -fsSL https://chatgpt.com/codex/install.sh | sh ;;
    herdr)  curl -fsSL https://herdr.dev/install.sh | sh ;;
    pi)     curl -fsSL https://pi.dev/install.sh | sh ;;
    metaai) curl -fsSL https://dev.meta.ai/install.sh | bash ;;
    *) return 1 ;;
  esac
}

# herdr plugins, installed whenever herdr is present (chosen now or earlier).
# herdr builds auto-title from source, so it needs Go - provided by mise.
# herdr-bar is plain Python 3 (stdlib only).
HERDR_PLUGINS=(
  kryptamine/herdr-auto-title
  jeffarese/herdr-bar
)
HERDR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"

_herdr_go() {
  if have go; then "$@"; else mise exec go -- "$@"; fi
}

install_herdr_plugins() {
  have herdr || return 0
  local installed p
  installed="$(herdr plugin list 2>/dev/null)"
  for p in "${HERDR_PLUGINS[@]}"; do
    if grep -qF "${p#*/}" <<<"$installed"; then
      skip "herdr plugin ${p#*/} (already installed)"
    elif _herdr_go herdr plugin install -y "$p" </dev/null; then
      ok "herdr plugin ${p#*/}"
    else
      warn "herdr plugin $p failed to install"
    fi
  done
  _herdr_bar_keybinding
  # Plugins only start with the herdr server; start them now if one runs.
  herdr plugin action invoke herdr.auto-title.restart >/dev/null 2>&1 || true
  herdr plugin action invoke herdr-bar.start-titles >/dev/null 2>&1 || true
}

# herdr adds no keybindings for plugins; bind the command bar to prefix+k.
_herdr_bar_keybinding() {
  herdr plugin list 2>/dev/null | grep -qF herdr-bar || return 0
  if grep -qF 'herdr-bar.open' "$HERDR_CONFIG" 2>/dev/null; then
    skip "herdr-bar keybinding (already in config.toml)"
    return 0
  fi
  mkdir -p "${HERDR_CONFIG%/*}"
  cat >>"$HERDR_CONFIG" <<'TOML'

[[keys.command]]
key = "prefix+k"
type = "plugin_action"
command = "herdr-bar.open"
description = "command bar"
TOML
  ok "herdr-bar on prefix+k (config.toml)"
  herdr server reload-config >/dev/null 2>&1 || true
}

# herdr's agent-state hooks for the agent CLIs present (Claude Code: a hook in
# ~/.claude/hooks plus a settings.json entry). Lets herdr, and auto-title,
# see what each agent is doing.
install_herdr_integrations() {
  have herdr || return 0
  if have claude || [[ -x $HOME/.local/bin/claude ]]; then
    if herdr integration status 2>/dev/null | grep -q '^claude: current'; then
      skip "herdr claude integration (already current)"
    elif herdr integration install claude >/dev/null </dev/null; then
      ok "herdr claude integration"
    else
      warn "herdr claude integration failed to install"
    fi
  fi
}

# The command each AI installer leaves behind (in ~/.local/bin, which may not
# be on PATH yet).
_ai_installed() {
  local bin="$1"
  [[ $1 == metaai ]] && bin=muse
  have "$bin" || [[ -x $HOME/.local/bin/$bin ]]
}

choose_ai_tools() {
  if [[ -n ${AI_TOOLS_ARG+x} ]]; then
    AI_TOOLS=()
    [[ -n $AI_TOOLS_ARG ]] && IFS=',' read -r -a AI_TOOLS <<<"$AI_TOOLS_ARG"
    return 0
  fi
  local -a menu=("${AI_MENU[@]}")
  dms_previous_run && read_lines menu < <(menu_from_state _ai_installed "${AI_MENU[@]}")
  read_lines AI_TOOLS < <(ui_multiselect "AI coding CLIs" "${menu[@]}")
}

install_ai_tools() {
  if [[ ${#AI_TOOLS[@]} -eq 0 ]]; then
    step "AI CLIs"; skip "none selected"; install_herdr_plugins; install_herdr_integrations; return 0
  fi
  step "AI CLIs (${AI_TOOLS[*]})"
  local t
  for t in "${AI_TOOLS[@]}"; do
    [[ -n $t ]] || continue
    log "installing $t"
    if _ai_install_one "$t" <&3; then ok "$t"; else warn "$t installer failed"; fi
  done
  install_herdr_plugins
  install_herdr_integrations
}
