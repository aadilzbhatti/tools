# tools

My dev setup in one command, for macOS and Linux: zsh + oh-my-zsh, vim, core CLI tools, Claude Code and Tailscale. On a Mac it also sets up iTerm2, VS Code and fonts. There's nothing to configure by hand afterwards.

```sh
curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash
```

For a headless Mac you SSH into (e.g. for remote Claude Code), use `--minimal`:

```sh
curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash -s -- --minimal
```

The installer only asks for your password if a step actually needs it, and asks at most once. Everything else runs on its own.

It's idempotent: anything already installed is left alone, so it's safe to re-run at any time. Once it's installed, `tools-update` re-runs it to pull this repo and update everything. It remembers the options you chose last time.

## Layout

```
install.sh            entry point: gets git + this repo, then runs ↓
scripts/macos.sh      Homebrew → base.sh → desktop apps + iTerm2 (full) or SSH/power settings (minimal)
scripts/base.sh       cross-platform (the whole install on Linux): packages, zsh, dotfiles, vim, Claude Code, Tailscale
scripts/tailscale.sh  Tailscale install + login; also runs standalone
scripts/lib.sh        shared helpers and flag parsing
```

## Options

| Flag | Effect |
| --- | --- |
| `--full` (default) | macOS: everything, including desktop apps |
| `--minimal` | macOS: skip GUI apps, fonts, VS Code and iTerm2. Turn on Remote Login (SSH), no system sleep on power, wake on network, restart after power loss |
| `--no-tailscale` | Don't install Tailscale (`--tailscale` turns it back on) |
| `--skip-packages` | Don't install/upgrade packages; just relink config. Not remembered |

`--minimal`/`--full` are ignored on Linux, which has no desktop part.

## What it does

| Step | Details |
| --- | --- |
| Prerequisites | macOS: Xcode CLT installed headlessly, then Homebrew non-interactively. Linux: git + curl |
| Packages | macOS: `brew bundle` from [`Brewfile`](Brewfile), plus [`Brewfile.desktop`](Brewfile.desktop) in full mode. Apps installed outside Homebrew are left alone. Linux: the same tools via apt, dnf or pacman |
| zsh | oh-my-zsh (unattended) with the `agnoster` theme; zsh becomes the login shell |
| Dotfiles | Symlinks [`zsh/zshrc`](zsh/zshrc), [`zsh/zshenv`](zsh/zshenv) and [`vim/vimrc`](vim/vimrc) into `~`. Existing files are backed up to `*.backup.<timestamp>` |
| Vim | [vim-plug](https://github.com/junegunn/vim-plug), with plugins installed during setup |
| Claude Code | Native installer, skipped if `claude` is already installed |
| Tailscale | Mac full mode: the menu bar app. Mac minimal mode: the headless daemon, which runs at boot with nobody logged in. Linux: system service. Set `TS_AUTHKEY` to join without the browser login |
| iTerm2 (Mac full) | Installs [`iterm2/profile.json`](iterm2/profile.json) as a [Dynamic Profile](https://iterm2.com/documentation-dynamic-profiles.html) (Solarized Dark, UbuntuMono Nerd Font 13pt, cmd/alt-arrow line and word jumps) and makes it the default |

The repo is cloned to `~/.tools`. To run from an existing checkout instead, use `./install.sh`. Set `TOOLS_DIR=...` to clone somewhere else.

## Using a remote machine from iTerm2

The look of the terminal (colors, font, key bindings) comes from iTerm2 on the machine you're typing on. The shell and vim setup come from the machine you SSH into. So:

- On your laptop: `install.sh` (full). This gives you the iTerm2 profile and the font the prompt symbols need.
- On the remote box: `install.sh --minimal` (Mac) or `install.sh` (Linux).
- Then `ssh <tailscale-hostname>`, or `tssh <host>` to attach to tmux as native iTerm2 tabs.

## Customizing

- **Packages:** edit `Brewfile` (everywhere) or `Brewfile.desktop` (Mac full mode only) and re-run. The Linux list is `LINUX_PACKAGES` in `scripts/base.sh`.
- **Machine-specific shell/vim config:** put it in `~/.zshrc.local` and `~/.vimrc.local`. Both files are sourced automatically and aren't tracked in this repo.
- **iTerm2 profile:** edit `iterm2/profile.json` and re-run. iTerm picks up the change live.
