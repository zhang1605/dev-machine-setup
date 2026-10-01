#!/usr/bin/env bash
# WSL integration: browser forwarding (so `gh auth login` and friends open
# the Windows host browser) and clipboard forwarding (WSL <-> Windows).
# shellcheck shell=bash

is_wsl() {
  [[ -n ${WSL_DISTRO_NAME:-} || -n ${WSLENV:-} ]] && return 0
  grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

# Best available command to open a URL on the Windows host.
wsl_browser_cmd() {
  if have wslview; then printf 'wslview'; return 0; fi
  if have wsl-open; then printf 'wsl-open'; return 0; fi
  if have powershell.exe; then printf 'powershell.exe start'; return 0; fi
  return 1
}

configure_wsl() {
  is_wsl || { skip "not WSL; skipping Windows-host integration"; return 0; }
  step "WSL integration (Windows host)"

  local browser=""
  browser="$(wsl_browser_cmd)" || true
  if [[ -n $browser ]]; then
    export BROWSER="$browser"
    export GH_BROWSER="$browser"
    ok "browser -> Windows host via $browser (BROWSER, GH_BROWSER)"
    log "gh auth login will open host Chrome/Edge automatically"
  else
    warn "no wslview/powershell.exe found; URLs will not open on the host"
    log "install wslu (provides wslview) or enable WSL interop"
  fi

  # Clipboard WSL -> Windows always works via clip.exe when interop is on;
  # Windows -> WSL needs powershell.exe. win32yank.exe covers both when the
  # user has installed it on the Windows side.
  if have win32yank.exe; then
    ok "clipboard via win32yank.exe (both directions)"
  elif have clip.exe && have powershell.exe; then
    ok "clipboard via clip.exe / powershell.exe (pbcopy/pbpaste in rc)"
  elif have clip.exe; then
    ok "clipboard out via clip.exe; paste needs powershell.exe"
  else
    warn "no Windows clipboard bridge found (clip.exe missing)"
    log "enable WSL interop or install win32yank.exe on Windows"
  fi

  # Wayland/X clipboard (WSLg) when present.
  if have wl-copy || have xclip; then
    ok "Linux GUI clipboard: $(have wl-copy && printf 'wl-clipboard ' ; have xclip && printf 'xclip')"
  else
    log "no wl-clipboard/xclip; terminal-only copy still works via clip.exe"
  fi
}
