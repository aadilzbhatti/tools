#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Cross-platform base setup (Linux and macOS): core CLI packages, zsh +
# oh-my-zsh, dotfiles, vim plugins, Claude Code and Tailscale. Idempotent.
#
# On Linux this is the whole install. On macOS, macos.sh runs this after
# installing Homebrew, then adds the Mac-only parts.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tailscale.sh
source "$TOOLS_DIR/scripts/tailscale.sh"

# Linux equivalents of the core Brewfile.
LINUX_PACKAGES=(git curl wget vim tmux zsh fzf ripgrep bat jq tree htop zoxide eza unzip)

install_linux_packages() {
  local pm install
  if command -v apt-get >/dev/null; then
    pm=apt; install=(env DEBIAN_FRONTEND=noninteractive apt-get install -y -q)
    as_root apt-get update -q </dev/null >/dev/null
    LINUX_PACKAGES+=(python3 python3-pip)
  elif command -v dnf >/dev/null; then
    pm=dnf; install=(dnf install -y -q)
    LINUX_PACKAGES=("${LINUX_PACKAGES[@]/#vim/vim-enhanced}" python3 python3-pip)
  elif command -v pacman >/dev/null; then
    pm=pacman; install=(pacman -S --needed --noconfirm)
    LINUX_PACKAGES+=(python python-pip)
  else
    warn "no supported package manager (apt, dnf, pacman); install packages yourself"
    return
  fi
  bold "Installing packages with $pm"
  # One batch first; if any name is missing on this distro (e.g. eza on older
  # Ubuntu), fall back to one at a time so the rest still get installed.
  if ! as_root "${install[@]}" "${LINUX_PACKAGES[@]}" </dev/null >/dev/null 2>&1; then
    local pkg missing=()
    for pkg in "${LINUX_PACKAGES[@]}"; do
      as_root "${install[@]}" "$pkg" </dev/null >/dev/null 2>&1 || missing+=("$pkg")
    done
    [[ ${#missing[@]} -gt 0 ]] && info "not available from $pm, skipped: ${missing[*]}"
  fi
  return 0
}

install_packages() {
  [[ "$SKIP_PACKAGES" == 1 ]] && return
  if [[ "$OS" == Darwin ]]; then
    if ! command -v brew >/dev/null; then
      warn "Homebrew not found; run install.sh (or scripts/macos.sh) instead"
      return
    fi
    bold "Installing packages from Brewfile"
    brew bundle --file="$TOOLS_DIR/Brewfile" </dev/null || warn "some Brewfile entries failed; see output above"
  else
    install_linux_packages
  fi
}

install_claude_code() {
  if command -v claude >/dev/null || [[ -x "$HOME/.local/bin/claude" ]]; then return; fi
  bold "Installing Claude Code"
  local script
  script=$(mktemp)
  if curl -fsSL https://claude.ai/install.sh -o "$script" && bash "$script" </dev/null; then
    info "installed; run \`claude\` once to sign in"
  else
    warn "Claude Code install failed"
  fi
  rm -f "$script"
}

login_shell() {
  if [[ "$OS" == Darwin ]]; then
    dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
  else
    getent passwd "$USER" | cut -d: -f7
  fi
}

# Check for oh-my-zsh.sh rather than just the directory: an interrupted install
# leaves a bare .git behind, and zsh then silently falls back to its default prompt.
install_oh_my_zsh() {
  local omz="$HOME/.oh-my-zsh"
  [[ -f "$omz/oh-my-zsh.sh" ]] && return
  bold "Installing oh-my-zsh"
  if [[ -e "$omz" ]]; then
    if [[ -d "$omz/.git" ]] && ! git -C "$omz" rev-parse --verify -q HEAD >/dev/null 2>&1; then
      info "removing incomplete $omz from an interrupted install"
      rm -rf "$omz"
    else
      warn "$omz exists but has no oh-my-zsh.sh; move it aside and re-run"
      return
    fi
  fi
  # Clone to a temp dir and rename, so an interrupted clone can't leave a half-install.
  local tmp="$omz.tmp.$$"
  if git clone --depth=1 -q https://github.com/ohmyzsh/ohmyzsh.git "$tmp" </dev/null; then
    mv "$tmp" "$omz"
  else
    rm -rf "$tmp"
    warn "couldn't clone oh-my-zsh; re-run to retry"
  fi
}

install_shell() {
  install_oh_my_zsh
  local zsh
  zsh=$(command -v zsh || true)
  if [[ -z "$zsh" ]]; then
    warn "zsh isn't installed; skipping login shell change"
  elif [[ "$(login_shell)" != */zsh ]]; then
    bold "Setting login shell to zsh"
    as_root chsh -s "$zsh" "$USER"
  fi
}

install_dotfiles() {
  bold "Linking dotfiles"
  link "$TOOLS_DIR/zsh/zshrc" "$HOME/.zshrc"
  link "$TOOLS_DIR/zsh/zshenv" "$HOME/.zshenv"
  link "$TOOLS_DIR/vim/vimrc" "$HOME/.vimrc"

  bold "Installing vim plugins"
  local plug="$HOME/.vim/autoload/plug.vim"
  [[ -f "$plug" ]] || curl -fsSLo "$plug" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  vim -E -s -u "$HOME/.vimrc" +'PlugUpdate --sync' +qall </dev/null >/dev/null 2>&1 \
    || warn "vim plugin install reported errors"
}

run_base() {
  install_packages
  install_shell
  install_dotfiles
  install_claude_code
  [[ "$NO_TAILSCALE" == 1 ]] || install_tailscale
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  parse_args "$@"
  bold "Setting up ($OS)"
  run_base
  finish "SSH in and run \`claude\` once to sign in to Claude Code."
fi
