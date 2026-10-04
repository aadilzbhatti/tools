#!/usr/bin/env bash
# One-command macOS setup. Idempotent: safe to re-run any time, and anything
# already installed is left alone.
#
#   curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash -s -- --minimal
#
# Everything lives in main() so a partially downloaded script never runs.
set -euo pipefail

REPO_URL="https://github.com/aadilzbhatti/tools.git"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.tools}"
STATE_DIR="$HOME/.config/tools"
ITERM_GUID="755E06F5-A164-4189-88F8-7FEB7FD8CBB3"

usage() {
  cat <<'EOF'
Usage: install.sh [--minimal | --full] [--skip-brew]

  --minimal    Headless dev box (for SSH / remote Claude Code): core CLI tools,
               zsh, vim, Claude Code, Remote Login on, no sleep. Skips GUI apps,
               fonts, VS Code and iTerm2.
  --full       Everything, including desktop apps (the default).
  --skip-brew  Don't install/upgrade Homebrew packages; just relink config.

The chosen mode is remembered, so a plain re-run (or `tools-update`) keeps it.
EOF
}

bold() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; WARNINGS+=("$*"); }
WARNINGS=()

# Only ask for a password when a step actually needs root, so re-runs on an
# already-set-up machine don't prompt at all.
SUDO_READY=0
need_sudo() {
  [[ $SUDO_READY == 1 ]] && return
  if ! sudo -n true 2>/dev/null; then
    bold "Requesting administrator access (asked once)"
    # Read the password from the terminal: under `curl | bash`, stdin is the script.
    # shellcheck disable=SC2024
    sudo -v </dev/tty
  fi
  while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  SUDO_READY=1
}

parse_args() {
  MODE=""
  SKIP_BREW="${SKIP_BREW:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --minimal) MODE=minimal ;;
      --full) MODE=full ;;
      --skip-brew) SKIP_BREW=1 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
  done
  if [[ -z "$MODE" ]]; then
    MODE=$(cat "$STATE_DIR/mode" 2>/dev/null || echo full)
  fi
  mkdir -p "$STATE_DIR"
  echo "$MODE" >"$STATE_DIR/mode"
}

install_clt() {
  xcode-select -p >/dev/null 2>&1 && return
  bold "Installing Xcode Command Line Tools"
  need_sudo
  # Headless install via softwareupdate, so there's no GUI prompt to click through.
  local marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
  touch "$marker"
  label=$(softwareupdate -l 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | sort -V | tail -n1)
  [[ -n "$label" ]] && sudo softwareupdate -i "$label" --verbose
  rm -f "$marker"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    echo "Finish the Command Line Tools install dialog, then re-run this script." >&2
    exit 1
  fi
}

install_homebrew() {
  local brew=""
  if [[ -x /opt/homebrew/bin/brew ]]; then brew=/opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then brew=/usr/local/bin/brew
  else
    bold "Installing Homebrew"
    need_sudo
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
    if [[ -x /opt/homebrew/bin/brew ]]; then brew=/opt/homebrew/bin/brew; else brew=/usr/local/bin/brew; fi
  fi
  eval "$("$brew" shellenv)"
}

# Clone or update the repo. If the script changed, re-exec the new version.
sync_repo() {
  local script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  fi
  if [[ -n "$script_dir" && -f "$script_dir/Brewfile" ]]; then
    TOOLS_DIR="$script_dir"
  elif [[ ! -d "$TOOLS_DIR/.git" ]]; then
    bold "Cloning tools into $TOOLS_DIR"
    git clone "$REPO_URL" "$TOOLS_DIR"
  fi

  if [[ -z "${TOOLS_REEXECED:-}" && -d "$TOOLS_DIR/.git" ]]; then
    local before after
    before=$(git -C "$TOOLS_DIR" rev-parse HEAD)
    git -C "$TOOLS_DIR" pull --ff-only --quiet </dev/null 2>/dev/null || warn "couldn't fast-forward $TOOLS_DIR (local changes?); using it as-is"
    after=$(git -C "$TOOLS_DIR" rev-parse HEAD)
    if [[ "$before" != "$after" ]]; then
      info "updated $TOOLS_DIR; restarting with the new installer"
      TOOLS_REEXECED=1 exec bash "$TOOLS_DIR/install.sh" --"$MODE" ${SKIP_BREW:+--skip-brew}
    fi
  fi

  # Keep ~/.tools pointing at the checkout so `tools-update` works.
  if [[ "$TOOLS_DIR" != "$HOME/.tools" && ! -e "$HOME/.tools" ]]; then
    ln -s "$TOOLS_DIR" "$HOME/.tools"
  fi
}

# Casks whose app/font already exists but wasn't installed by Homebrew (e.g. a
# manual iTerm download). `brew install` would error on those, so skip them.
casks_installed_elsewhere() {
  local file="$1" casks
  casks=$(brew bundle list --cask --file="$file" 2>/dev/null) || return 0
  [[ -z "$casks" ]] && return 0
  # shellcheck disable=SC2086
  brew info --json=v2 --cask $casks 2>/dev/null | MANAGED="$(brew list --cask 2>/dev/null)" /usr/bin/python3 -c '
import json, os, sys
managed = set(os.environ["MANAGED"].split())
dirs = {"app": "/Applications", "font": os.path.expanduser("~/Library/Fonts")}

def targets(cask):
    for artifact in cask["artifacts"]:
        for kind, base in dirs.items():
            for entry in artifact.get(kind, []):
                name = entry.get("target") if isinstance(entry, dict) else entry
                if isinstance(name, str):
                    yield os.path.join(base, os.path.basename(name))

for cask in json.load(sys.stdin)["casks"]:
    if cask["token"] not in managed and any(map(os.path.exists, targets(cask))):
        print(cask["token"])
' | sort -u | tr '\n' ' '
}

run_bundle() {
  local file="$1" skip
  [[ -f "$file" ]] || return 0
  bold "Installing packages from $(basename "$file")"
  skip=$(casks_installed_elsewhere "$file")
  [[ -n "$skip" ]] && info "already installed outside Homebrew, leaving alone: $skip"
  HOMEBREW_BUNDLE_CASK_SKIP="$skip" brew bundle --file="$file" </dev/null \
    || warn "some entries in $(basename "$file") failed; see output above"
}

install_packages() {
  [[ "$SKIP_BREW" == 1 ]] && return
  # A manually installed VS Code has no `code` on PATH; use its bundled CLI
  # so the extension entries still work.
  local vscode_bin="/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
  if ! command -v code >/dev/null && [[ -d "$vscode_bin" ]]; then
    export PATH="$PATH:$vscode_bin"
  fi
  run_bundle "$TOOLS_DIR/Brewfile"
  [[ "$MODE" == full ]] && run_bundle "$TOOLS_DIR/Brewfile.desktop"
  return 0
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

install_shell() {
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    bold "Installing oh-my-zsh"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended </dev/null
  fi
  if [[ "$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')" != */zsh ]]; then
    bold "Setting login shell to zsh"
    need_sudo
    sudo chsh -s /bin/zsh "$USER"
  fi
}

# Symlink a dotfile; an existing different file is backed up first.
link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then return; fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    local backup
    backup="$dst.backup.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$backup"
    info "backed up $dst -> $backup"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  info "linked $dst"
}

install_dotfiles() {
  bold "Linking dotfiles"
  link "$TOOLS_DIR/zsh/zshrc" "$HOME/.zshrc"
  link "$TOOLS_DIR/vim/vimrc" "$HOME/.vimrc"

  bold "Installing vim plugins"
  local plug="$HOME/.vim/autoload/plug.vim"
  [[ -f "$plug" ]] || curl -fsSLo "$plug" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  vim -E -s -u "$HOME/.vimrc" +'PlugUpdate --sync' +qall </dev/null >/dev/null 2>&1 \
    || warn "vim plugin install reported errors"
}

# ps rather than pgrep: pgrep can't always see GUI apps. No `grep -q`, since
# its early exit would SIGPIPE ps and fail the pipeline under pipefail.
iterm_running() {
  # shellcheck disable=SC2009
  ps -axo comm= | grep "/iTerm.app/Contents/MacOS/iTerm2$" >/dev/null
}

configure_iterm() {
  bold "Configuring iTerm2"
  # Dynamic Profiles are picked up automatically, no import step needed.
  # Copied rather than symlinked: iTerm2 doesn't reliably watch symlink targets.
  local dyn="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  mkdir -p "$dyn"
  cp "$TOOLS_DIR/iterm2/profile.json" "$dyn/tools.json"
  local current
  current=$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)
  if [[ "$current" == "$ITERM_GUID" ]]; then
    return
  elif iterm_running; then
    # iTerm rewrites its prefs on quit, which would undo the change.
    warn "iTerm2 is running; quit it and re-run to make the profile the default"
  else
    defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$ITERM_GUID"
  fi
}

# --minimal: make this Mac reachable and keep it awake.
configure_server() {
  bold "Configuring for remote access"
  if nc -z -G 2 localhost 22 >/dev/null 2>&1; then
    info "Remote Login (SSH) already on"
  else
    need_sudo
    sudo systemsetup -setremotelogin on >/dev/null 2>&1 \
      || { sudo launchctl enable system/com.openssh.sshd && sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist; } >/dev/null 2>&1 \
      || true
    if nc -z -G 2 localhost 22 >/dev/null 2>&1; then
      info "turned on Remote Login (SSH)"
    else
      warn "couldn't turn on Remote Login; enable it in System Settings > General > Sharing > Remote Login"
    fi
  fi

  # No system sleep on power (display can still sleep), wake on network,
  # and boot back up after a power cut.
  local want=(sleep 0 disksleep 0 womp 1 autorestart 1) changes=() i current
  for ((i = 0; i < ${#want[@]}; i += 2)); do
    current=$(pmset -g custom | awk -v k="${want[i]}" '/^AC Power/ { ac = 1; next } /^[^ ]/ { ac = 0 } ac && $1 == k && !done { print $2; done = 1 }')
    [[ "$current" != "${want[i+1]}" ]] && changes+=("${want[i]}" "${want[i+1]}")
  done
  if [[ ${#changes[@]} -eq 0 ]]; then
    info "power settings already server-friendly"
  else
    need_sudo
    if sudo pmset -c "${changes[@]}" >/dev/null 2>&1; then
      info "set power: ${changes[*]}"
    else
      warn "couldn't update power settings (pmset ${changes[*]})"
    fi
  fi
}

main() {
  [[ "$(uname -s)" == "Darwin" ]] || { echo "This installer is for macOS." >&2; exit 1; }
  parse_args "$@"
  bold "Setting up in $MODE mode"

  install_clt
  install_homebrew
  sync_repo
  install_packages
  install_claude_code
  install_shell
  install_dotfiles
  if [[ "$MODE" == minimal ]]; then configure_server; else configure_iterm; fi

  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    bold "Done, with warnings:"
    printf '  - %s\n' "${WARNINGS[@]}"
  else
    bold "Done!"
  fi
  if [[ "$MODE" == minimal ]]; then
    info "SSH in and run \`claude\` once to sign in to Claude Code."
  else
    info "Open a new iTerm2 window to see everything."
  fi
  info "Re-run any time with: tools-update"
}

main "$@"
