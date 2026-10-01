#!/usr/bin/env bash
# Assertions that only mean something after the installer has run at least
# twice on the same box. Run it there, after the second run.
#
#   bash test/idempotency.sh
#
# Uses find rather than globs: under zsh a non-matching glob aborts the
# command, which would make these checks pass for the wrong reason.
set -u
fails=0

count_lines() { [ -f "$2" ] && grep -c -- "$1" "$2" || echo 0; }
count_paths() { find "$(dirname "$1")" -maxdepth 1 -name "$(basename "$1")" 2>/dev/null | wc -l | tr -d ' '; }

chk() {
  local label="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "  PASS $label ($got)"
  else
    echo "  FAIL $label: got $got, want $want"
    fails=1
  fi
}

echo "-- managed block appears exactly once --"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  chk "$(basename "$rc") begin marker" "$(count_lines '^# >>> dev-machine-setup >>>' "$rc")" 1
  chk "$(basename "$rc") end marker"   "$(count_lines '^# <<< dev-machine-setup <<<' "$rc")" 1
done

echo "-- shell init lines not duplicated --"
chk "atuin init zsh"    "$(count_lines 'atuin init zsh'    "$HOME/.zshrc")"  1
chk "atuin init bash"   "$(count_lines 'atuin init bash'   "$HOME/.bashrc")" 1
chk "mise activate zsh" "$(count_lines 'mise activate zsh' "$HOME/.zshrc")"  1
chk "zoxide init zsh"   "$(count_lines 'zoxide init zsh'   "$HOME/.zshrc")"  1
chk "alias ll"          "$(count_lines 'alias ll='         "$HOME/.zshrc")"  1
chk "wsl block"         "$(count_lines 'wsl (browser'       "$HOME/.zshrc")"  1

echo "-- re-runs must not manufacture backups --"
chk "nvim backups"        "$(count_paths "$HOME/.config/nvim.dms-backup.*")"             0
chk "tmux backups"        "$(count_paths "$HOME/.tmux.dms-backup.*")"                    0
chk "tmux.conf backups"   "$(count_paths "$HOME/.tmux.conf.dms-backup.*")"               0
chk "mise config backups" "$(count_paths "$HOME/.config/mise/config.toml.dms-backup.*")" 0

echo
if [ "$fails" = 0 ]; then echo "IDEMPOTENCY OK"; else echo "IDEMPOTENCY FAILED"; fi
exit "$fails"
