# dev-machine-config

One command to take a bare Ubuntu or Arch box to a working dev machine.

```sh
curl -fsSL https://herdr.dev/install.sh | sh
```

Non-interactive (CI, cloud-init, Dockerfile):

```sh
curl -fsSL https://herdr.dev/install.sh | sh -s -- --yes --email=navex --ai=claude
```

> **Before this works you have to host `install.sh` and push this repo.**
> See [Hosting](#hosting).

## What it does

| # | Step | Detail |
|---|------|--------|
| 1 | System packages | `apt` on Ubuntu/Debian, `pacman` on Arch (plus `yay-bin` from the AUR). Build toolchain, `zsh`, `vim`, `tmux`, `fzf`, `ripgrep`, `fd`, `jq`, and the headers mise/Homebrew want. |
| 2 | [mise](https://mise.jdx.dev) | Installed from `mise.run`, then a generated global `~/.config/mise/config.toml`. |
| 3 | mise tools | python 3.13, uv, go, node 23, bun, lazygit, aws-cli, gh, eza, zoxide, neovim — plus whatever optional packs you pick. |
| 4 | oh-my-zsh | `--unattended`, keeps an existing `.zshrc`. |
| 5 | atuin | Shell history. Run `atuin register` yourself if you want sync. |
| 6 | Homebrew | Linuxbrew at `/home/linuxbrew/.linuxbrew`. Skipped when running as root. |
| 7 | tmux | `gpakosz/.tmux` cloned to `~/.tmux`, symlinked, `.tmux.conf.local` seeded. |
| 8 | Neovim | `MichaelZhang-Navex/lazyvim-starter` branch `michael` → `~/.config/nvim`. |
| 9 | AI CLIs | Multi-select: Claude Code, Codex, herdr, pi, Meta AI. |
| 10 | Shell + git | Managed block in `.zshrc`/`.bashrc`, `chsh` to zsh, global git config. |

Every prompt is asked **up front**, so the slow part runs unattended.

## Interactive choices

- **Optional mise tools** — terraform, terragrunt, changie, duckdb (all on by
  default), snowflake-cli (off by default; the pipx install is slow).
- **AI CLIs** — Claude Code on by default, the rest off.
- **git identity** — `michael.zhang@navex.com`, `zhang1605@gmail.com`, or type
  your own. `user.name` defaults to `Michael Zhang`.

The menus are arrow-key checkboxes (`↑`/`↓` or `j`/`k`, `space`, `a`, `n`,
`enter`, `q` to abort). They read `/dev/tty` on fd 3, so they work even though
`curl | sh` has already claimed stdin. With no tty at all the installer says so
and falls back to defaults.

## Layout

```
install.sh          POSIX-sh bootstrap: prereqs, clone, hand off
bootstrap.sh        orchestrator: args, prompts, module dispatch, summary
lib/common.sh       logging, distro detect, sudo, managed file blocks, tty UI
lib/pkgs.sh         apt / pacman + yay
lib/mise.sh         mise install, global config.toml, tool install
lib/shell.sh        oh-my-zsh, .zshrc/.bashrc block, default shell
lib/extras.sh       atuin, tmux, LazyVim starter, Homebrew
lib/ai.sh           AI CLI multi-select
lib/git.sh          global git config
bin/dev-machine     re-run / update wrapper (symlinked to ~/.local/bin)
test/unit.sh        offline unit tests (no root, no network)
test/docker.sh      end-to-end run in ubuntu:24.04 and archlinux containers
test/verify.sh      post-install assertions
```

## Re-running

The checkout stays at `~/.dev-machine-config` and `dev-machine` lands on your
`PATH`:

```sh
dev-machine update                  # git pull, then full re-run
dev-machine run --only=mise         # just refresh mise tools
dev-machine run --only=shell,git    # just rewrite the rc block + git config
dev-machine run --skip=brew,ai      # everything except those
dev-machine modules                 # pkgs mise omz atuin brew tmux nvim ai git shell
```

Re-runs are idempotent: package installs use `--needed`/`-y`, clones are
detected and pulled instead of re-cloned, and the rc block is replaced in place
between its markers rather than appended.

```
# >>> dev-machine-config >>>
...generated...
# <<< dev-machine-config <<<
```

Put your own customisations **outside** those markers and they survive.

## Options

```
-y, --yes                Non-interactive; take every default.
    --only=A,B           Run only these modules.
    --skip=A,B           Run everything except these modules.
    --mise-extras=A,B    terraform terragrunt changie duckdb snowflake ("" for none)
    --ai=A,B             claude codex herdr pi metaai ("" for none)
    --email=X            navex | personal | any@address
    --name="X"           git user.name
    --list-modules       Print module names and exit.
-h, --help
```

Environment overrides: `DMC_REPO`, `DMC_BRANCH`, `DMC_DIR`,
`DMC_NVIM_REPO`, `DMC_NVIM_BRANCH`, `NO_COLOR`.

## Anything it won't do for you

- **Backups, not merges.** An existing `~/.config/nvim`, `~/.tmux`, or a
  hand-written `mise/config.toml` is moved to `<path>.dmc-backup.<timestamp>`
  and the warning is repeated in the final summary.
- **`atuin register`/`login`** — your call, it needs credentials.
- **Plugin bootstrap** — the first `nvim` launch installs LazyVim's plugins.
- **Homebrew as root** is skipped (brew refuses); everything else works as root.

## Hosting

`install.sh` hardcodes where to clone from:

```sh
REPO="${DMC_REPO:-https://github.com/MichaelZhang-Navex/dev-machine-config.git}"
```

1. Push this repo to that URL (or edit the default).
2. Serve `install.sh` at `https://herdr.dev/install.sh`. Any of these work:
   - a redirect to `https://raw.githubusercontent.com/<you>/dev-machine-config/main/install.sh`
   - Cloudflare Workers / Pages, or an S3 object behind the domain
   - a one-line nginx `location = /install.sh`

   Note `herdr.dev/install.sh` is also one of the AI CLI installers in step 9 —
   pick a path or host that doesn't collide with it.
3. Until it's hosted, the long form works everywhere:

```sh
git clone https://github.com/MichaelZhang-Navex/dev-machine-config ~/.dev-machine-config
bash ~/.dev-machine-config/bootstrap.sh
```

## Testing

```sh
bash test/unit.sh          # fast, offline, safe on any machine
bash test/docker.sh        # real installs in ubuntu:24.04 + archlinux
bash test/verify.sh        # assertions, run on a box you just provisioned
```

`test/unit.sh` covers managed-block idempotency, generated `config.toml`
(parsed and asserted with `tomllib`), generated rc files (`bash -n` plus content
checks, including that atuin's own installer lines aren't duplicated), argument
parsing, and the `--only`/`--skip` filter.

## Supported

Ubuntu / Debian / Pop / Mint / elementary / Zorin, and Arch / Manjaro /
EndeavourOS / Garuda. Detected from `/etc/os-release` (`ID`, then `ID_LIKE`).
Root or a sudo user both work.
