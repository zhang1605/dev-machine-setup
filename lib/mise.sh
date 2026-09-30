#!/usr/bin/env bash
# mise: install the binary, write the global config, install the tools.
# shellcheck shell=bash

MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}"
MISE_CONFIG="$MISE_CONFIG_DIR/config.toml"
MISE_MARKER='# managed by dev-machine-config'

# Always installed.
MISE_CORE_TOOLS=(
  "python = '3.13'"
  "uv = 'latest'"
  "go = 'latest'"
  "node = '23'"
  "bun = 'latest'"
  "lazygit = 'latest'"
  "aws-cli = 'latest'"
  "gh = 'latest'"
  "eza = 'latest'"
  "zoxide = 'latest'"
  "neovim = 'latest'"
)

# key|label|default
MISE_EXTRA_MENU=(
  "terraform|terraform|on"
  "terragrunt|terragrunt  ${C_DIM}(github:gruntwork-io/terragrunt)${C_RESET}|on"
  "changie|changie|on"
  "duckdb|duckdb|on"
  "snowflake|snowflake-cli  ${C_DIM}(pipx; slower install)${C_RESET}|off"
)

_mise_extra_line() {
  case "$1" in
    terraform)  printf "terraform = 'latest'\n" ;;
    terragrunt) printf '"github:gruntwork-io/terragrunt" = '"'latest'\n" ;;
    changie)    printf "changie = 'latest'\n" ;;
    duckdb)     printf "duckdb = 'latest'\n" ;;
    snowflake)  printf "'pipx:snowflake-cli' = 'latest'\n" ;;
  esac
}

choose_mise_extras() {
  if [[ -n ${MISE_EXTRAS_ARG+x} ]]; then
    MISE_EXTRAS=()
    [[ -n $MISE_EXTRAS_ARG ]] && IFS=',' read -r -a MISE_EXTRAS <<<"$MISE_EXTRAS_ARG"
    return 0
  fi
  read_lines MISE_EXTRAS < <(ui_multiselect "Optional mise tools" "${MISE_EXTRA_MENU[@]}")
}

install_mise() {
  step "mise"
  if have mise; then
    skip "mise already installed ($(mise --version 2>/dev/null | head -1))"
  else
    curl -fsSL https://mise.run | MISE_QUIET=1 sh
    ok "mise installed"
  fi

  export PATH="$HOME/.local/bin:$PATH"
  have mise || die "mise not on PATH after install (expected ~/.local/bin/mise)"
}

write_mise_config() {
  step "mise global config"
  mkdir -p "$MISE_CONFIG_DIR"

  if [[ -f $MISE_CONFIG ]] && ! head -1 "$MISE_CONFIG" | grep -qF "$MISE_MARKER"; then
    cp "$MISE_CONFIG" "$MISE_CONFIG.dmc-backup.$(date +%Y%m%d%H%M%S)"
    warn "backed up your existing $MISE_CONFIG"
  fi

  {
    printf '%s\n' "$MISE_MARKER"
    printf '%s\n\n' "# edit freely - re-running the installer will back this up before replacing it"
    printf '[tools]\n'
    printf '%s\n' "${MISE_CORE_TOOLS[@]}"
    local e
    for e in "${MISE_EXTRAS[@]}"; do
      [[ -n $e ]] && _mise_extra_line "$e"
    done
    printf '\n[settings.node]\ngpg_verify = false\n'
    cat <<'TOML'

[shell_alias]
l = "eza --git -l -o --no-permissions --header"
claude = "claude --dangerously-skip-permissions"
ca = "claude --dangerously-skip-permissions"
TOML
  } >"$MISE_CONFIG"

  ok "wrote $MISE_CONFIG"
  log "tools: ${#MISE_CORE_TOOLS[@]} core + ${#MISE_EXTRAS[@]} optional"
}

install_mise_tools() {
  step "Installing mise tools (this is the slow part)"
  if mise install --yes; then
    ok "mise tools installed"
  else
    warn "some mise tools failed; run 'mise install' again to retry"
  fi
  mise ls --current 2>/dev/null | sed 's/^/    /' >&2 || true
}
