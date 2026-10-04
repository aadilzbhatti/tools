#!/usr/bin/env bash
# One-command macOS setup. Safe to re-run any time (it's idempotent).
#
#   curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash
#
# Env vars:
#   TOOLS_DIR=~/.tools   where the repo gets cloned
#   SKIP_BREW=1          skip `brew bundle` (just link dotfiles)
set -euo pipefail

REPO_URL="https://github.com/aadilzbhatti/tools.git"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.tools}"
ITERM_GUID="755E06F5-A164-4189-88F8-7FEB7FD8CBB3"

bold() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "This installer is for macOS." >&2; exit 1; }

# Ask for the password once up front and keep sudo alive, so nothing later
# stops halfway to prompt (Homebrew's non-interactive install needs this).
bold "Requesting administrator access (asked once)"
sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

# --- Xcode Command Line Tools (git, compilers) --------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
  bold "Installing Xcode Command Line Tools"
  # Headless install via softwareupdate, so there's no GUI prompt to click through.
  marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  touch "$marker"
  label=$(softwareupdate -l 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | sort -V | tail -n1)
  if [[ -n "$label" ]]; then
    sudo softwareupdate -i "$label" --verbose
  fi
  rm -f "$marker"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    echo "Finish the Command Line Tools install dialog, then re-run this script." >&2
    exit 1
  fi
fi

# --- Homebrew -----------------------------------------------------------------
if [[ -x /opt/homebrew/bin/brew ]]; then BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then BREW=/usr/local/bin/brew
else
  bold "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then BREW=/opt/homebrew/bin/brew; else BREW=/usr/local/bin/brew; fi
fi
eval "$("$BREW" shellenv)"

# --- Get this repo ------------------------------------------------------------
# If run from a checkout, use it; otherwise clone/update ~/.tools.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/Brewfile" ]]; then
  TOOLS_DIR="$SCRIPT_DIR"
elif [[ -d "$TOOLS_DIR/.git" ]]; then
  bold "Updating $TOOLS_DIR"
  git -C "$TOOLS_DIR" pull --ff-only || warn "couldn't fast-forward $TOOLS_DIR; using it as-is"
else
  bold "Cloning tools into $TOOLS_DIR"
  git clone "$REPO_URL" "$TOOLS_DIR"
fi
# Keep `~/.tools` pointing at the checkout so the `tools-update` alias works.
if [[ "$TOOLS_DIR" != "$HOME/.tools" && ! -e "$HOME/.tools" ]]; then
  ln -s "$TOOLS_DIR" "$HOME/.tools"
fi

# --- Packages -----------------------------------------------------------------
if [[ "${SKIP_BREW:-}" != 1 ]]; then
  bold "Installing packages from Brewfile (this can take a while the first time)"
  brew bundle --file="$TOOLS_DIR/Brewfile" || warn "some Brewfile entries failed; see output above"
fi

# --- oh-my-zsh ----------------------------------------------------------------
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  bold "Installing oh-my-zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
if [[ "$(dscl . -read "/Users/$USER" UserShell | awk '{print $2}')" != */zsh ]]; then
  bold "Setting login shell to zsh"
  sudo chsh -s /bin/zsh "$USER"
fi

# --- Dotfiles (symlinked; existing files are backed up once) ------------------
link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then return; fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    local backup
    backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$backup"
    echo "  backed up $dst -> $backup"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "  linked $dst"
}
bold "Linking dotfiles"
link "$TOOLS_DIR/zsh/zshrc" "$HOME/.zshrc"
link "$TOOLS_DIR/vim/vimrc" "$HOME/.vimrc"

# --- Vim plugins ----------------------------------------------------------------
bold "Installing vim plugins"
plug="$HOME/.vim/autoload/plug.vim"
[[ -f "$plug" ]] || curl -fsSLo "$plug" --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
vim -E -s -u "$HOME/.vimrc" +'PlugUpdate --sync' +qall </dev/null >/dev/null 2>&1 || warn "vim plugin install reported errors"

# --- iTerm2 -------------------------------------------------------------------
# Dynamic Profiles are picked up automatically by iTerm2, no import step needed.
bold "Configuring iTerm2"
dyn="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
mkdir -p "$dyn"
# Copied rather than symlinked: iTerm2 doesn't reliably watch symlink targets.
cp "$TOOLS_DIR/iterm2/profile.json" "$dyn/tools.json"
# Make it the default profile. iTerm rewrites its prefs on quit, so only do
# this while it isn't running (otherwise it'd be overwritten).
if pgrep -xq iTerm2; then
  warn "iTerm2 is running; quit it and re-run to make the profile the default (or pick it in Settings > Profiles)"
else
  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$ITERM_GUID"
fi

bold "Done! Open a new iTerm2 window to see everything. Re-run any time with: tools-update"
