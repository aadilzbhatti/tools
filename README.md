# tools

My macOS setup in one command: iTerm2 + oh-my-zsh, Homebrew packages, VS Code, vim, and fonts. There's nothing to configure by hand afterwards.

```sh
curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash
```

The installer asks for your password once at the start. After that it runs on its own. It's safe to re-run, and once it's installed, `tools-update` re-runs it to pull this repo and update everything.

## What it does

| Step | Details |
| --- | --- |
| Xcode CLT | Installed headlessly via `softwareupdate`, so there's no dialog to click through |
| Homebrew | Non-interactive install, works on both Apple Silicon and Intel |
| Packages | `brew bundle` from [`Brewfile`](Brewfile): iTerm2, VS Code (+ extensions), Nerd Font, CLI tools |
| oh-my-zsh | Unattended install, `agnoster` theme, `git`/`fzf`/`zoxide` plugins |
| Dotfiles | Symlinks [`zsh/zshrc`](zsh/zshrc) → `~/.zshrc` and [`vim/vimrc`](vim/vimrc) → `~/.vimrc`. Existing files are backed up to `*.backup.<timestamp>` |
| Vim | [vim-plug](https://github.com/junegunn/vim-plug), with plugins installed during setup |
| iTerm2 | Installs [`iterm2/profile.json`](iterm2/profile.json) as a [Dynamic Profile](https://iterm2.com/documentation-dynamic-profiles.html) (Solarized Dark, UbuntuMono Nerd Font 13pt, cmd/alt-arrow line and word jumps) and makes it the default |

The repo is cloned to `~/.tools`. To run from an existing checkout instead, use `./install.sh`.

Options: `SKIP_BREW=1 ./install.sh` relinks dotfiles without touching packages, and `TOOLS_DIR=...` changes the clone location.

## Customizing

- **Packages:** edit `Brewfile` and re-run.
- **Machine-specific shell/vim config:** put it in `~/.zshrc.local` and `~/.vimrc.local`. Both files are sourced automatically and aren't tracked in this repo.
- **iTerm2 profile:** edit `iterm2/profile.json` and re-run. iTerm picks up the change live.

## Extras

- `tssh <host>` sshes into a host and attaches to tmux using iTerm2's native tmux integration (`tmux -CC`).
