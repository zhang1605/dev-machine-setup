#!/usr/bin/env bash
# Post-install assertions. Run inside a freshly provisioned box or container
# after a full `--yes --email=navex` run.
#
#   bash test/verify.sh
#
set -u
export PATH="$HOME/.local/bin:$HOME/.atuin/bin:$PATH"
fails=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  PASS $1"; else echo "  FAIL $1"; fails=1; fi; }

echo "-- mise --"
check "mise on PATH"             'command -v mise'
check "mise config exists"       'test -f "$HOME/.config/mise/config.toml"'
check "python 3.13"              'mise exec -- python --version | grep -q " 3\.13"'
check "node 23"                  'mise exec -- node --version | grep -q "^v23"'
check "go"                       'mise which go'
check "uv"                       'mise which uv'
check "bun"                      'mise which bun'
check "eza"                      'mise which eza'
check "zoxide"                   'mise which zoxide'
check "neovim"                   'mise which nvim'
check "lazygit"                  'mise which lazygit'
check "gh"                       'mise which gh'
check "aws-cli"                  'mise which aws'
check "terraform"                'mise which terraform'
check "duckdb"                   'mise which duckdb'

echo "-- system packages --"
check "zsh"                      'command -v zsh'
check "fzf"                      'command -v fzf'
check "ripgrep"                  'command -v rg'
check "fd"                       'command -v fd'
check "tmux"                     'command -v tmux'
check "build toolchain"          'command -v cc || command -v gcc'

echo "-- extras --"
check "oh-my-zsh present"        'test -d "$HOME/.oh-my-zsh"'
check "atuin"                    'command -v atuin'
check "tmux.conf symlinked"      'test -L "$HOME/.tmux.conf"'
check "tmux.conf.local copied"   'test -f "$HOME/.tmux.conf.local"'
check "nvim config cloned"       'test -d "$HOME/.config/nvim/.git"'
check "homebrew"                 'test -x /home/linuxbrew/.linuxbrew/bin/brew'
check "dev-machine on PATH"      'command -v dev-machine'

echo "-- shell wiring --"
check "zshrc managed block"      'grep -q "dev-machine-setup" "$HOME/.zshrc"'
check "bashrc managed block"     'grep -q "dev-machine-setup" "$HOME/.bashrc"'
check "zsh is default shell"     'getent passwd "$(id -un)" | grep -q zsh'
check "mise activates in zsh"    'zsh -lic "command -v mise"'
check "shell_alias l works"      'zsh -lic "alias l" | grep -q eza'

echo "-- git --"
check "user.email set"           'git config --global user.email | grep -q "@"'
check "user.name set"            'git config --global user.name | grep -q .'
check "core.editor is nvim"      'test "$(git config --global core.editor)" = nvim'
check "init.defaultBranch main"  'test "$(git config --global init.defaultBranch)" = main'

echo
if [ "$fails" = 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit "$fails"
