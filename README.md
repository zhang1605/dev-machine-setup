# dev-machine-setup

One command to take a bare Ubuntu or Arch box to a working dev machine.

```sh
curl -fsSL https://raw.githubusercontent.com/zhang1605/dev-machine-setup/main/install.sh | sh
```

That is the real, working command — nothing to host first. Run it on the new
box and answer three prompts.

Non-interactive (CI, cloud-init, Dockerfile), no prompts at all:

```sh
curl -fsSL https://raw.githubusercontent.com/zhang1605/dev-machine-setup/main/install.sh | sh -s -- --yes --email=navex --ai=claude
```

Running as **root** (ArchWSL boots as root with no user-setup step, unlike
Ubuntu WSL)? The installer creates a user first — default `michael` — asks
for a password, then runs everything as that user:

```sh
sh install.sh --user=michael
```

On **WSL** it also forwards URLs (`gh auth login`, etc.) to the Windows host
browser via `wslview`, and wires `pbcopy`/`pbpaste` to the Windows clipboard
(`win32yank.exe` when installed, else `clip.exe` / `powershell.exe`).

If you'd rather not pipe a URL into a shell sight unseen — reasonable — read it
first, then run the same file:

```sh
curl -fsSL https://raw.githubusercontent.com/zhang1605/dev-machine-setup/main/install.sh -o install.sh
less install.sh
sh install.sh
```

## What it does

| # | Step | Detail |
|---|------|--------|
| 0 | User account | Running as root (typical ArchWSL): create user `michael` (prompt, `--user=` overrides), set a password, passwordless sudo, then re-run the whole install as that user. Non-root runs skip this. |
| 1 | System packages | `apt` on Ubuntu/Debian, `pacman` on Arch (plus `yay-bin` from the AUR). Build toolchain, `zsh`, `vim`, `tmux`, `fzf`, `ripgrep`, `fd`, `jq`, `wslu` (Arch: from the AUR, WSL only) + clipboard tools, and the headers mise/Homebrew want. |
| 2 | [mise](https://mise.jdx.dev) | Installed from `mise.run`, then a generated global `~/.config/mise/config.toml`. |
| 3 | mise tools | python 3.13, uv, go, node 23, bun, lazygit, aws-cli, gh, eza, zoxide, neovim — plus whatever optional packs you pick. |
| 4 | oh-my-zsh | `--unattended`, keeps an existing `.zshrc`. Theme set to `bira`. |
| 5 | atuin | Shell history. Run `atuin register` yourself if you want sync. |
| 6 | Homebrew | Linuxbrew at `/home/linuxbrew/.linuxbrew`. Skipped when running as root. |
| 7 | tmux | `gpakosz/.tmux` cloned to `~/.tmux`, symlinked, `.tmux.conf.local` seeded. |
| 8 | Neovim | `MichaelZhang-Navex/lazyvim-starter` branch `michael` → `~/.config/nvim`. |
| 9 | AI CLIs | Multi-select: Claude Code, Codex, herdr, pi, Meta AI. |
| 10 | Shell + git | Managed block in `.zshrc`/`.bashrc`, `ZSH_THEME`, `chsh` to zsh, global git config. |
| 11 | WSL integration | No-op off WSL. On WSL: `BROWSER`/`GH_BROWSER` → host browser (`wslview`), `pbcopy`/`pbpaste` → Windows clipboard; warns when interop helpers are missing. |

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
lib/user.sh         root -> user bootstrap (create michael, sudoers, re-exec)
lib/wsl.sh          WSL detect, host browser + clipboard checks
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

The checkout stays at `~/.dev-machine-setup` and `dev-machine` lands on your
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
# >>> dev-machine-setup >>>
...generated...
# <<< dev-machine-setup <<<
```

Put your own customisations **outside** those markers and they survive.

## Options

```
-y, --yes                Non-interactive; take every default.
    --user=NAME          Linux user to create/use when running as root
                         (prompted, default: michael).
    --only=A,B           Run only these modules.
    --skip=A,B           Run everything except these modules.
    --mise-extras=A,B    terraform terragrunt changie duckdb snowflake ("" for none)
    --ai=A,B             claude codex herdr pi metaai ("" for none)
    --email=X            navex | personal | any@address
    --name="X"           git user.name
    --theme=X            oh-my-zsh theme (default: bira)
    --list-modules       Print module names and exit.
-h, --help
```

Environment overrides: `DMS_REPO`, `DMS_BRANCH`, `DMS_DIR`,
`DMS_NVIM_REPO`, `DMS_NVIM_BRANCH`, `DMS_ZSH_THEME`, `NO_COLOR`.

## Anything it won't do for you

- **Backups, not merges.** An existing `~/.config/nvim`, `~/.tmux`, or a
  hand-written `mise/config.toml` is moved to `<path>.dms-backup.<timestamp>`
  and the warning is repeated in the final summary.
- **`atuin register`/`login`** — your call, it needs credentials.
- **Plugin bootstrap** — the first `nvim` launch installs LazyVim's plugins.
- **Homebrew as root** is skipped (brew refuses); everything else works as root.

## A shorter URL, if you ever want one

Entirely optional. The raw GitHub URL above needs no hosting and no DNS, and
`curl -fsSL` follows redirects, so a domain you own can just point at it:

- a 302 from `https://<your-domain>/install.sh` to the raw URL
- Cloudflare Workers / Pages, or an S3 object behind the domain
- a one-line nginx `location = /install.sh`

Where the clone comes from is a separate knob, in case you fork this:

```sh
REPO="${DMS_REPO:-https://github.com/zhang1605/dev-machine-setup.git}"   # install.sh
```

`DMS_REPO`, `DMS_BRANCH` and `DMS_DIR` all override it at runtime, so a fork
needs no edit:

```sh
curl -fsSL .../install.sh | DMS_BRANCH=my-branch sh
```

Or skip `install.sh` and clone by hand — it only exists to do this for you:

```sh
git clone https://github.com/zhang1605/dev-machine-setup ~/.dev-machine-setup
bash ~/.dev-machine-setup/bootstrap.sh
```

## Testing

```sh
bash test/unit.sh                      # fast, offline, safe on any machine
bash test/docker.sh                    # real installs in ubuntu:24.04 + archlinux
DMS_TWICE=1 bash test/docker.sh ubuntu # install twice, assert idempotency
bash test/verify.sh                    # run on a box you just provisioned
bash test/idempotency.sh               # run there after a second install
```

`test/unit.sh` (72 checks) covers managed-block replacement, the generated
`config.toml` (parsed and asserted with `tomllib`), the generated rc files
(`bash -n` plus content checks, including that atuin's own installer lines
aren't duplicated), argument parsing, the `--only`/`--skip` filter, the
root-to-user default (`michael`, `--user=`), WSL detection/browser
preference, and the WSL rc block (valid shell, not duplicated).

`test/docker.sh` does a real end-to-end install and then runs
`test/verify.sh` (45 checks: every tool resolved through `mise which`, python
and node pinned versions asserted, `[shell_alias]` and `$ZSH_THEME` exercised
through `zsh -lic`, the `chsh` change read back out of `/etc/passwd`,
plus `wslview` presence and the WSL rc block).

### Last verified

Both distros, `--platform linux/amd64`, 2026-09-30: **40/40, no warnings**,
about 1m35s each. A second run on the same box is clean too — 14/14 in
`test/idempotency.sh`, no warnings, no manufactured `.dms-backup.*`.

The documented one-liner is verified separately, on bare `ubuntu:24.04` and
`archlinux` containers with no `git` installed: it installs the prerequisites,
clones, runs, and ends at `VERIFY OK`. Worth testing that path specifically —
`test/docker.sh` copies the repo in and calls `bootstrap.sh` directly, so it
never exercises `install.sh` itself.

> Pushing a change does not update the one-liner immediately.
> `raw.githubusercontent.com` sends `max-age=300`, so the URL serves the
> previous version for up to five minutes, and a query-string cache-buster
> does not help. Check with `curl -sI <url> | grep source-age`.

## Supported

Ubuntu / Debian / Pop / Mint / elementary / Zorin, and Arch / Manjaro /
EndeavourOS / Garuda. Detected from `/etc/os-release` (`ID`, then `ID_LIKE`).
Root or a sudo user both work.
