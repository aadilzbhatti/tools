# tools

My macOS setup in one command: iTerm2 + oh-my-zsh, Homebrew packages, VS Code, vim, and fonts. There's nothing to configure by hand afterwards.

```sh
curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash
```

For a headless dev box you SSH into (e.g. for remote Claude Code), use `--minimal`:

```sh
curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash -s -- --minimal
```

The installer only asks for your password if a step actually needs it, and asks at most once. Everything else runs on its own.

It's idempotent: anything already installed is left alone, so it's safe to re-run at any time. Once it's installed, `tools-update` re-runs it to pull this repo and update everything. It remembers whether you last chose `--minimal` or `--full`.

## Modes

| | `--full` (default) | `--minimal` |
| --- | --- | --- |
| Core CLI ([`Brewfile`](Brewfile)): git, gh, tmux, vim, fzf, ripgrep, node, python, … | ✓ | ✓ |
| zsh + oh-my-zsh, vim config + plugins, Claude Code | ✓ | ✓ |
| Desktop apps ([`Brewfile.desktop`](Brewfile.desktop)): iTerm2, VS Code + extensions, Nerd Font | ✓ | |
| iTerm2 profile | ✓ | |
| Remote Login (SSH) on; no system sleep on power; wake on network; restart after power loss | | ✓ |

## What it does

| Step | Details |
| --- | --- |
| Xcode CLT | Installed headlessly via `softwareupdate`, so there's no dialog to click through |
| Homebrew | Non-interactive install, works on both Apple Silicon and Intel |
| Packages | `brew bundle` from [`Brewfile`](Brewfile) (and [`Brewfile.desktop`](Brewfile.desktop) in full mode). Apps you installed manually, outside Homebrew, are detected and left alone |
| Claude Code | Native installer, skipped if `claude` is already installed |
| oh-my-zsh | Unattended install, `agnoster` theme, `git`/`fzf`/`zoxide` plugins |
| Dotfiles | Symlinks [`zsh/zshrc`](zsh/zshrc) → `~/.zshrc` and [`vim/vimrc`](vim/vimrc) → `~/.vimrc`. Existing files are backed up to `*.backup.<timestamp>` |
| Vim | [vim-plug](https://github.com/junegunn/vim-plug), with plugins installed during setup |
| iTerm2 (full) | Installs [`iterm2/profile.json`](iterm2/profile.json) as a [Dynamic Profile](https://iterm2.com/documentation-dynamic-profiles.html) (Solarized Dark, UbuntuMono Nerd Font 13pt, cmd/alt-arrow line and word jumps) and makes it the default |

The repo is cloned to `~/.tools`. To run from an existing checkout instead, use `./install.sh`.

Options: `--skip-brew` relinks config without touching packages, and `TOOLS_DIR=...` changes the clone location. Run `./install.sh --help` for the full list.

## Customizing

- **Packages:** edit `Brewfile` (everywhere) or `Brewfile.desktop` (full mode only) and re-run.
- **Machine-specific shell/vim config:** put it in `~/.zshrc.local` and `~/.vimrc.local`. Both files are sourced automatically and aren't tracked in this repo.
- **iTerm2 profile:** edit `iterm2/profile.json` and re-run. iTerm picks up the change live.

## Extras

- `tssh <host>` sshes into a host and attaches to tmux using iTerm2's native tmux integration (`tmux -CC`).
