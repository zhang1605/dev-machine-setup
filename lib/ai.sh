#!/usr/bin/env bash
# AI coding CLIs - all opt-in via multi-select.
# shellcheck shell=bash

# key|label|default
AI_MENU=(
  "claude|Claude Code       ${C_DIM}claude.ai/install.sh${C_RESET}|on"
  "codex|Codex CLI          ${C_DIM}chatgpt.com/codex/install.sh${C_RESET}|off"
  "herdr|herdr              ${C_DIM}herdr.dev/install.sh${C_RESET}|off"
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
# herdr builds them from source, so they need Go - provided by mise.
HERDR_PLUGINS=(
  kryptamine/herdr-auto-title
)

_herdr_go() {
  if have go; then "$@"; else mise exec go -- "$@"; fi
}

install_herdr_plugins() {
  have herdr || return 0
  have go || have mise || { warn "herdr plugins need Go; skipping"; return 0; }
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
  # Plugins only start with the herdr server; start auto-title now if one runs.
  herdr plugin action invoke herdr.auto-title.restart >/dev/null 2>&1 || true
}

choose_ai_tools() {
  if [[ -n ${AI_TOOLS_ARG+x} ]]; then
    AI_TOOLS=()
    [[ -n $AI_TOOLS_ARG ]] && IFS=',' read -r -a AI_TOOLS <<<"$AI_TOOLS_ARG"
    return 0
  fi
  read_lines AI_TOOLS < <(ui_multiselect "AI coding CLIs" "${AI_MENU[@]}")
}

install_ai_tools() {
  if [[ ${#AI_TOOLS[@]} -eq 0 ]]; then
    step "AI CLIs"; skip "none selected"; install_herdr_plugins; return 0
  fi
  step "AI CLIs (${AI_TOOLS[*]})"
  local t
  for t in "${AI_TOOLS[@]}"; do
    [[ -n $t ]] || continue
    log "installing $t"
    if _ai_install_one "$t" <&3; then ok "$t"; else warn "$t installer failed"; fi
  done
  install_herdr_plugins
}
