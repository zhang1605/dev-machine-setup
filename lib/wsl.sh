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

# Windows .exe interop rides on the WSLInterop binfmt_misc entry. Under
# systemd, WSL's drop-in for systemd-binfmt.service re-registers it - but that
# unit is skipped when every binfmt.d dir is empty (stock Arch), and the entry
# can go missing, leaving every .exe failing with "exec format error". A
# binfmt.d file makes the unit run on each boot; register now for this boot.
WSL_BINFMT_CONF=/etc/binfmt.d/WSLInterop.conf
WSL_BINFMT_RULE=':WSLInterop:M::MZ::/init:PF'

ensure_wsl_interop() {
  [[ -x /init ]] || return 0
  if [[ ! -f $WSL_BINFMT_CONF ]]; then
    $SUDO mkdir -p "${WSL_BINFMT_CONF%/*}"
    printf '%s\n' "$WSL_BINFMT_RULE" | $SUDO tee "$WSL_BINFMT_CONF" >/dev/null \
      && ok "persisted Windows interop in $WSL_BINFMT_CONF"
  fi
  local bm=/proc/sys/fs/binfmt_misc
  [[ -e $bm/register ]] || return 0
  if [[ -e $bm/WSLInterop ]]; then
    ok "Windows interop registered (WSLInterop)"
  elif printf '%s\n' "$WSL_BINFMT_RULE" | $SUDO tee "$bm/register" >/dev/null 2>&1; then
    ok "re-registered Windows interop (WSLInterop was missing)"
  else
    warn "Windows interop not registered; .exe files will not run"
    log "try 'wsl --shutdown' from Windows, then reopen the distro"
  fi
}

# `su -` in the root -> user re-exec drops the Windows PATH entries, so fall
# back to System32 when looking for the host's clipboard tools.
have_win() { have "$1" || [[ -x /mnt/c/Windows/System32/$1 ]]; }

configure_wsl() {
  is_wsl || { skip "not WSL; skipping Windows-host integration"; return 0; }
  step "WSL integration (Windows host)"

  ensure_wsl_interop

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
  elif have_win clip.exe && have_win WindowsPowerShell/v1.0/powershell.exe; then
    ok "clipboard via clip.exe / powershell.exe (pbcopy/pbpaste in rc)"
  elif have_win clip.exe; then
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
