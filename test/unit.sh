#!/usr/bin/env bash
# Unit tests for the pure-logic pieces: file blocks, config generation,
# argument handling. No network, no package manager, no root.
#
#   bash test/unit.sh
#
set -uo pipefail
ROOT="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
TMP="$(mktemp -d)"
export HOME="$TMP/home"; mkdir -p "$HOME"
NONINTERACTIVE=1
declare -a WARNINGS=()
FAIL=0
# t <label> <got> [want]   - want defaults to 0, so exit-status checks still work
t() {
  want="${3:-0}"
  if [ "$2" = "$want" ]; then
    printf '  PASS %s\n' "$1"
  else
    printf '  FAIL %s (got %s, want %s)\n' "$1" "$2" "$want"; FAIL=1
  fi
}
has(){ grep -qF "$2" "$1"; }

source "$ROOT/lib/common.sh"
source "$ROOT/lib/mise.sh"
source "$ROOT/lib/shell.sh"
source "$ROOT/lib/ai.sh"
source "$ROOT/lib/git.sh"
source "$ROOT/lib/user.sh"
source "$ROOT/lib/wsl.sh"
NONINTERACTIVE=1
IS_ROOT=0

echo "== write_block idempotency =="
F="$TMP/rc"
printf 'export MINE=1\n' > "$F"
write_block "$F" "line-a
line-b"
write_block "$F" "line-a
line-b"
t "user content preserved"    "$(has "$F" 'export MINE=1'; echo $?)"
t "exactly one begin marker"  "$([ "$(grep -cF "$BLOCK_BEGIN" "$F")" = 1 ] && echo 0 || echo 1)"
t "exactly one end marker"    "$([ "$(grep -cF "$BLOCK_END" "$F")" = 1 ] && echo 0 || echo 1)"
t "body present once"         "$([ "$(grep -cF 'line-a' "$F")" = 1 ] && echo 0 || echo 1)"
write_block "$F" "replaced"
t "block replaced, not appended" "$([ "$(grep -cF 'line-a' "$F")" = 0 ] && echo 0 || echo 1)"

echo "== legacy dev-machine-config block is adopted, not orphaned =="
L="$TMP/legacy-rc"
{ printf 'export MINE=1\n'
  printf '%s\n' "$LEGACY_BEGIN"
  printf 'export PATH="/old/path:$PATH"\n'
  printf '%s\n' "$LEGACY_END"
  printf 'export AFTER=1\n'; } > "$L"
write_block "$L" "fresh-body"
t "legacy begin marker gone"  "$([ "$(grep -cF "$LEGACY_BEGIN" "$L")" = 0 ] && echo 0 || echo 1)"
t "legacy end marker gone"    "$([ "$(grep -cF "$LEGACY_END" "$L")" = 0 ] && echo 0 || echo 1)"
t "legacy body gone"          "$([ "$(grep -cF '/old/path' "$L")" = 0 ] && echo 0 || echo 1)"
t "new marker present once"   "$([ "$(grep -cF "$BLOCK_BEGIN" "$L")" = 1 ] && echo 0 || echo 1)"
t "user lines around it kept" "$(grep -qF 'export MINE=1' "$L" && grep -qF 'export AFTER=1' "$L"; echo $?)"

echo "== non-interactive defaults =="
choose_mise_extras
t "mise defaults = terraform terragrunt changie duckdb" \
  "$([ "${MISE_EXTRAS[*]}" = "terraform terragrunt changie duckdb" ] && echo 0 || echo 1)"
MISE_EXTRAS_ARG="terraform,duckdb" choose_mise_extras
t "--mise-extras respected" "$([ "${MISE_EXTRAS[*]}" = "terraform duckdb" ] && echo 0 || echo 1)"
MISE_EXTRAS_ARG="" choose_mise_extras
t "--mise-extras= means none" "$([ "${#MISE_EXTRAS[@]}" = 0 ] && echo 0 || echo 1)"
choose_ai_tools
t "ai default = claude" "$([ "${AI_TOOLS[*]}" = "claude" ] && echo 0 || echo 1)"
AI_TOOLS_ARG="claude,codex,pi" choose_ai_tools
t "--ai respected" "$([ "${AI_TOOLS[*]}" = "claude codex pi" ] && echo 0 || echo 1)"
GIT_EMAIL_ARG=personal choose_git_identity
t "--email=personal" "$([ "$GIT_EMAIL" = "zhang1605@gmail.com" ] && echo 0 || echo 1)"
GIT_EMAIL_ARG=navex choose_git_identity
t "--email=navex" "$([ "$GIT_EMAIL" = "michael.zhang@navex.com" ] && echo 0 || echo 1)"
GIT_EMAIL_ARG="a@b.co" choose_git_identity
t "--email=custom" "$([ "$GIT_EMAIL" = "a@b.co" ] && echo 0 || echo 1)"

echo "== mise config.toml =="
MISE_CONFIG_DIR="$TMP/miseconf"; MISE_CONFIG="$MISE_CONFIG_DIR/config.toml"
choose_mise_extras
write_mise_config >/dev/null 2>&1
t "config written" "$([ -f "$MISE_CONFIG" ] && echo 0 || echo 1)"
python3 - "$MISE_CONFIG" <<'PY'
import sys,tomllib
d=tomllib.load(open(sys.argv[1],'rb'))
tools=d['tools']
exp={'python':'3.13','uv':'latest','go':'latest','node':'23','bun':'latest','lazygit':'latest',
     'aws-cli':'latest','gh':'latest','eza':'latest','zoxide':'latest','neovim':'latest',
     'terraform':'latest','github:gruntwork-io/terragrunt':'latest','changie':'latest','duckdb':'latest'}
missing=[k for k,v in exp.items() if tools.get(k)!=v]
assert not missing, f"missing/wrong: {missing}"
assert d['settings']['node']['gpg_verify'] is False, "gpg_verify"
al=d['shell_alias']
assert al['l']=="eza --git -l -o --no-permissions --header", al
assert al['claude']=="claude --dangerously-skip-permissions"
assert al['ca']=="claude --dangerously-skip-permissions"
assert 'pipx:snowflake-cli' not in tools, "snowflake should be off by default"
print("  PASS valid TOML with all expected keys")
PY
[ $? = 0 ] || FAIL=1
# snowflake variant
MISE_EXTRAS_ARG="snowflake" choose_mise_extras; write_mise_config >/dev/null 2>&1
python3 -c "
import tomllib,sys
d=tomllib.load(open('$MISE_CONFIG','rb'))
assert d['tools']['pipx:snowflake-cli']=='latest'
assert 'terraform' not in d['tools']
print('  PASS snowflake-only variant is valid TOML')" || FAIL=1
# backup on foreign config
printf 'x = 1\n' > "$MISE_CONFIG"
write_mise_config >/dev/null 2>&1
t "foreign config backed up" "$(ls "$MISE_CONFIG_DIR"/config.toml.dms-backup.* >/dev/null 2>&1; echo $?)"

echo "== rc body =="
Z="$HOME/.zshrc"; : > "$Z"
write_block "$Z" "$(_rc_body zsh "$Z")"
bash -n "$Z"; t "generated zshrc is valid shell" $?
for n in 'mise activate zsh' 'atuin init zsh' 'zoxide init zsh' 'fzf --zsh' 'linuxbrew' 'EDITOR="nvim"' '.local/bin' '.atuin/bin'; do
  t "zshrc contains: $n" "$(has "$Z" "$n"; echo $?)"
done
# atuin already configured by its own installer -> don't duplicate
Z2="$HOME/.zshrc2"; printf 'eval "$(atuin init zsh)"\n' > "$Z2"
write_block "$Z2" "$(_rc_body zsh "$Z2")"
t "atuin init not duplicated" "$([ "$(grep -cF 'atuin init zsh' "$Z2")" = 1 ] && echo 0 || echo 1)"
B="$HOME/.bashrc"; : > "$B"
write_block "$B" "$(_rc_body bash "$B")"
bash -n "$B"; t "generated bashrc is valid shell" $?
t "bashrc uses bash init" "$(has "$B" 'mise activate bash'; echo $?)"

echo "== zsh theme (must land above the oh-my-zsh source line) =="
mk_omz_rc() {
  cat > "$1" <<'RC'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
export MINE=1
RC
}
ZSHRC="$TMP/theme-rc"; mk_omz_rc "$ZSHRC"
set_zsh_theme >/dev/null 2>&1
t "theme replaced"            "$(grep -c '^ZSH_THEME="bira"' "$ZSHRC")" 1
t "old theme gone"            "$(grep -c 'robbyrussell' "$ZSHRC")" 0
t "exactly one ZSH_THEME"     "$(grep -c '^[[:space:]]*ZSH_THEME=' "$ZSHRC")" 1
theme_ln=$(grep -n '^ZSH_THEME=' "$ZSHRC" | cut -d: -f1)
src_ln=$(grep -n 'oh-my-zsh.sh' "$ZSHRC" | cut -d: -f1)
t "theme precedes omz source" "$([ "$theme_ln" -lt "$src_ln" ] && echo 0 || echo 1)"
t "user lines preserved"      "$(grep -qF 'export MINE=1' "$ZSHRC" && grep -qF 'plugins=(git)' "$ZSHRC"; echo $?)"
set_zsh_theme >/dev/null 2>&1
t "idempotent (still one)"    "$(grep -c '^[[:space:]]*ZSH_THEME=' "$ZSHRC")" 1

# assignment stripped, but oh-my-zsh is still sourced
ZSHRC="$TMP/theme-rc2"
printf 'export ZSH="$HOME/.oh-my-zsh"\nsource $ZSH/oh-my-zsh.sh\n' > "$ZSHRC"
set_zsh_theme >/dev/null 2>&1
t "inserted when absent"      "$(grep -c '^ZSH_THEME="bira"' "$ZSHRC")" 1
theme_ln=$(grep -n '^ZSH_THEME=' "$ZSHRC" | cut -d: -f1)
src_ln=$(grep -n 'oh-my-zsh.sh' "$ZSHRC" | cut -d: -f1)
t "inserted above source"     "$([ "$theme_ln" -lt "$src_ln" ] && echo 0 || echo 1)"

# no oh-my-zsh at all: leave the file alone
ZSHRC="$TMP/theme-rc3"; printf 'export MINE=1\n' > "$ZSHRC"
set_zsh_theme >/dev/null 2>&1 && rc=0 || rc=1
t "skips without oh-my-zsh"   "$rc" 1
t "file untouched"            "$(cat "$ZSHRC")" "export MINE=1"

# override
ZSH_THEME_NAME="agnoster"; ZSHRC="$TMP/theme-rc4"; mk_omz_rc "$ZSHRC"
set_zsh_theme >/dev/null 2>&1
t "DMS_ZSH_THEME override"    "$(grep -c '^ZSH_THEME="agnoster"' "$ZSHRC")" 1
ZSH_THEME_NAME="bira"

echo "== bootstrap argument handling =="
out="$(bash "$ROOT/bootstrap.sh" --list-modules 2>&1)"
t "--list-modules lists 10 modules" "$([ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 10 ] && echo 0 || echo 1)"
bash "$ROOT/bootstrap.sh" --help >/dev/null 2>&1; t "--help exits 0" $?
bash "$ROOT/bootstrap.sh" --bogus >/dev/null 2>&1; t "unknown flag exits 2" "$([ $? = 2 ] && echo 0 || echo 1)"
t "--help documents --user" "$(bash "$ROOT/bootstrap.sh" --help 2>&1 | grep -q -- '--user=NAME'; echo $?)"

echo "== dev user selection (root bootstrap) =="
DMS_USER_ARG="michael" choose_dev_user
t "--user=michael respected" "$([ "$TARGET_USER" = "michael" ] && echo 0 || echo 1)"
DMS_USER_ARG="" choose_dev_user
t "default user is michael" "$([ "$TARGET_USER" = "michael" ] && echo 0 || echo 1)"
DMS_USER_ARG="Alice_X-1" choose_dev_user
t "username lowercased" "$([ "$TARGET_USER" = "alice_x-1" ] && echo 0 || echo 1)"
DMS_USER_ARG=""
IS_ROOT=0; ensure_dev_user; t "non-root: user step is a no-op" $?

echo "== wsl detection =="
unset WSL_DISTRO_NAME WSLENV
if is_wsl; then t "not WSL here" 1 0; else t "not WSL here" 0; fi
WSL_DISTRO_NAME=Ubuntu is_wsl; t "WSL_DISTRO_NAME detected" $?
WSLENV=WT_SESSION is_wsl; t "WSLENV detected" $?
unset WSL_DISTRO_NAME WSLENV

echo "== wsl browser preference =="
t "no browser without helpers" "$(PATH=/nonexistent wsl_browser_cmd >/dev/null 2>&1; echo $((1 - $?)))"
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/wslview"; chmod +x "$FAKEBIN/wslview"
t "wslview preferred" "$([ "$(PATH="$FAKEBIN:/usr/bin:/bin" wsl_browser_cmd)" = wslview ] && echo 0 || echo 1)"
rm "$FAKEBIN/wslview"
printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/powershell.exe"; chmod +x "$FAKEBIN/powershell.exe"
t "powershell fallback" "$([ "$(PATH="$FAKEBIN:/usr/bin:/bin" wsl_browser_cmd)" = "powershell.exe start" ] && echo 0 || echo 1)"

echo "== wsl rc block =="
ZW="$HOME/.zshrc-wsl"; : > "$ZW"
write_block "$ZW" "$(_rc_body zsh "$ZW")"
bash -n "$ZW"; t "zshrc with wsl block is valid shell" $?
for n in 'wslview' 'GH_BROWSER' 'pbcopy' 'clip.exe' 'WSL_DISTRO_NAME'; do
  t "zshrc contains: $n" "$(has "$ZW" "$n"; echo $?)"
done
c1="$(grep -cF 'wslview' "$ZW")"
write_block "$ZW" "$(_rc_body zsh "$ZW")"
t "wsl block not duplicated" "$([ "$(grep -cF 'wslview' "$ZW")" = "$c1" ] && echo 0 || echo 1)"

echo "== enabled() module filter =="
ONLY=""; SKIP=""
_in_csv() { [[ ",$1," == *",$2,"* ]]; }
enabled() { local m="$1"; [[ -n $ONLY ]] && { _in_csv "$ONLY" "$m"; return; }; [[ -n $SKIP ]] && { _in_csv "$SKIP" "$m" && return 1; }; return 0; }
enabled mise; t "default: mise enabled" $?
ONLY="mise,shell"; enabled mise; t "--only: mise enabled" $?
enabled pkgs; t "--only: pkgs disabled" "$([ $? = 1 ] && echo 0 || echo 1)"
ONLY=""; SKIP="brew,ai"; enabled brew; t "--skip: brew disabled" "$([ $? = 1 ] && echo 0 || echo 1)"
enabled mise; t "--skip: mise still enabled" $?

rm -rf "$TMP"
echo
[ $FAIL = 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
