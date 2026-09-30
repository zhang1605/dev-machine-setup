#!/usr/bin/env bash
# atuin, tmux (gpakosz), LazyVim starter, Homebrew.
# shellcheck shell=bash

install_atuin() {
  step "atuin"
  if have atuin || [[ -x $HOME/.atuin/bin/atuin ]]; then
    skip "atuin already installed"
    return 0
  fi

  # --non-interactive is load-bearing, not just a preference. Without it the
  # upstream script runs `if { exec 3</dev/tty; } 2>/dev/null` under `set -e`,
  # and a failed exec redirection makes a non-interactive shell exit - so it
  # dies silently, before its own banner, on any box without a tty. The flag
  # skips that block entirely.
  if curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive; then
    export PATH="$HOME/.atuin/bin:$PATH"
    ok "atuin installed"
    log "run 'atuin register' (or 'atuin login') if you want history sync"
  else
    warn "atuin install failed"
  fi
}

install_tmux_conf() {
  step "tmux config (gpakosz/.tmux)"
  local dir="$HOME/.tmux"

  if [[ -d $dir/.git ]]; then
    git -C "$dir" pull --quiet --ff-only 2>/dev/null || true
    skip "gpakosz/.tmux already present (pulled)"
  else
    backup_path "$dir"
    git clone --depth 1 https://github.com/gpakosz/.tmux.git "$dir" \
      || { warn "tmux config clone failed"; return 1; }
  fi

  # Same wiring the upstream install.sh does, minus its prompts.
  ln -sfn "$dir/.tmux.conf" "$HOME/.tmux.conf"
  if [[ ! -f $HOME/.tmux.conf.local ]]; then
    cp "$dir/.tmux.conf.local" "$HOME/.tmux.conf.local"
  else
    skip "kept your existing ~/.tmux.conf.local"
  fi
  ok "tmux configured (~/.tmux.conf -> $dir/.tmux.conf)"
}

install_lazyvim() {
  step "Neovim config (LazyVim starter)"
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  local repo="${DMS_NVIM_REPO:-https://github.com/MichaelZhang-Navex/lazyvim-starter}"
  local branch="${DMS_NVIM_BRANCH:-michael}"

  if [[ -d $dir/.git ]]; then
    skip "$dir is already a git checkout (leaving it alone)"
    return 0
  fi

  backup_path "$dir"
  if git clone "$repo" "$dir" --branch "$branch"; then
    ok "cloned $repo#$branch -> $dir"
    log "first 'nvim' launch will bootstrap lazy.nvim plugins"
  else
    warn "LazyVim starter clone failed"
  fi
}

install_homebrew() {
  step "Homebrew"
  if have brew || [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    skip "Homebrew already installed"
    return 0
  fi
  if [[ ${IS_ROOT:-0} -eq 1 ]]; then
    warn "Homebrew refuses to install as root; skipping"
    return 0
  fi

  log "this pulls a few hundred MB and takes a while"
  if NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    local brew_bin=/home/linuxbrew/.linuxbrew/bin/brew
    [[ -x $brew_bin ]] && eval "$("$brew_bin" shellenv)"
    ok "Homebrew installed"
  else
    warn "Homebrew install failed"
  fi
}
