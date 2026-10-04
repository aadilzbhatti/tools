#!/usr/bin/env bash
# One-command setup for macOS and Linux. Idempotent: safe to re-run any time,
# and anything already installed is left alone.
#
#   curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/aadilzbhatti/tools/master/install.sh | bash -s -- --minimal
#
# This only bootstraps (git + a checkout of this repo), then hands off to
# scripts/macos.sh or scripts/base.sh. Run with --help for options.
#
# Everything lives in main() so a partially downloaded script never runs.
set -euo pipefail

REPO_URL="https://github.com/aadilzbhatti/tools.git"
TOOLS_DIR="${TOOLS_DIR:-$HOME/.tools}"

bold() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

# sudo reads the password from the terminal: under `curl | bash`, stdin is the script.
# shellcheck disable=SC2024
as_root() {
  if [[ $EUID == 0 ]]; then "$@"; else sudo "$@" </dev/tty; fi
}

# git comes from the Xcode Command Line Tools on macOS.
install_clt() {
  xcode-select -p >/dev/null 2>&1 && return
  bold "Installing Xcode Command Line Tools"
  # Headless install via softwareupdate, so there's no GUI prompt to click through.
  local marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
  touch "$marker"
  label=$(softwareupdate -l 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | sort -V | tail -n1)
  [[ -n "$label" ]] && as_root softwareupdate -i "$label" --verbose
  rm -f "$marker"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    echo "Finish the Command Line Tools install dialog, then re-run this script." >&2
    exit 1
  fi
}

install_linux_git() {
  command -v git >/dev/null && command -v curl >/dev/null && return
  bold "Installing git and curl"
  if command -v apt-get >/dev/null; then
    as_root apt-get update -q && as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q git curl
  elif command -v dnf >/dev/null; then
    as_root dnf install -y -q git curl
  elif command -v pacman >/dev/null; then
    as_root pacman -S --needed --noconfirm git curl
  else
    echo "Install git and curl, then re-run this script." >&2
    exit 1
  fi
}

# Clone or update the repo. If this script changed, re-exec the new version.
sync_repo() {
  local script_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  fi
  if [[ -n "$script_dir" && -f "$script_dir/scripts/base.sh" ]]; then
    TOOLS_DIR="$script_dir"
  elif [[ ! -d "$TOOLS_DIR/.git" ]]; then
    bold "Cloning tools into $TOOLS_DIR"
    git clone "$REPO_URL" "$TOOLS_DIR"
  fi

  if [[ -z "${TOOLS_REEXECED:-}" && -d "$TOOLS_DIR/.git" ]]; then
    local before after
    before=$(git -C "$TOOLS_DIR" rev-parse HEAD)
    git -C "$TOOLS_DIR" pull --ff-only --quiet </dev/null 2>/dev/null \
      || printf '\033[1;33mwarn:\033[0m %s\n' "couldn't fast-forward $TOOLS_DIR (local changes?); using it as-is" >&2
    after=$(git -C "$TOOLS_DIR" rev-parse HEAD)
    if [[ "$before" != "$after" ]] && ! git -C "$TOOLS_DIR" diff --quiet "$before" "$after" -- install.sh; then
      TOOLS_REEXECED=1 exec bash "$TOOLS_DIR/install.sh" "$@"
    fi
  fi

  # Keep ~/.tools pointing at the checkout so `tools-update` works.
  if [[ "$TOOLS_DIR" != "$HOME/.tools" && ! -e "$HOME/.tools" ]]; then
    ln -s "$TOOLS_DIR" "$HOME/.tools"
  fi
}

main() {
  case "$(uname -s)" in
    Darwin) install_clt ;;
    Linux) install_linux_git ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
  sync_repo "$@"
  if [[ "$(uname -s)" == Darwin ]]; then
    exec bash "$TOOLS_DIR/scripts/macos.sh" "$@"
  else
    exec bash "$TOOLS_DIR/scripts/base.sh" "$@"
  fi
}

main "$@"
