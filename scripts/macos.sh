#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# macOS setup: Homebrew, then everything in base.sh, then the Mac-only parts
# (desktop apps + iTerm2 in --full, SSH/power settings in --minimal).
# Idempotent: anything already installed is left alone.
set -euo pipefail
# shellcheck source=base.sh
source "$(dirname "${BASH_SOURCE[0]}")/base.sh"

ITERM_GUID="755E06F5-A164-4189-88F8-7FEB7FD8CBB3"

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

install_desktop_packages() {
  [[ "$SKIP_PACKAGES" == 1 ]] && return
  local file="$TOOLS_DIR/Brewfile.desktop" skip
  bold "Installing packages from Brewfile.desktop"
  # A manually installed VS Code has no `code` on PATH; use its bundled CLI
  # so the extension entries still work.
  local vscode_bin="/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
  if ! command -v code >/dev/null && [[ -d "$vscode_bin" ]]; then
    export PATH="$PATH:$vscode_bin"
  fi
  skip=$(casks_installed_elsewhere "$file")
  [[ -n "$skip" ]] && info "already installed outside Homebrew, leaving alone: $skip"
  HOMEBREW_BUNDLE_CASK_SKIP="$skip" brew bundle --file="$file" </dev/null \
    || warn "some entries in Brewfile.desktop failed; see output above"
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

parse_args "$@"
bold "Setting up macOS in $MODE mode"
install_homebrew
run_base
if [[ "$MODE" == minimal ]]; then
  configure_server
  finish "SSH in and run \`claude\` once to sign in to Claude Code."
else
  install_desktop_packages
  configure_iterm
  finish "Open a new iTerm2 window to see everything."
fi
