# Shared helpers, sourced by the other scripts. Not meant to be run directly.
# shellcheck shell=bash disable=SC2034  # vars here are used by the scripts that source this

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE_DIR="$HOME/.config/tools"
OS="$(uname -s)"   # Darwin or Linux

bold() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; WARNINGS+=("$*"); }
WARNINGS=()

# Only ask for a password when a step actually needs root, so re-runs on an
# already-set-up machine don't prompt at all.
SUDO_READY=0
need_sudo() {
  [[ $SUDO_READY == 1 || $EUID == 0 ]] && return
  if ! sudo -n true 2>/dev/null; then
    bold "Requesting administrator access (asked once)"
    # Read the password from the terminal: under `curl | bash`, stdin is the script.
    # shellcheck disable=SC2024
    sudo -v </dev/tty
  fi
  while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  SUDO_READY=1
}
as_root() {
  if [[ $EUID == 0 ]]; then "$@"; else need_sudo; sudo "$@"; fi
}

# Flags shared by every script. Unknown flags are an error.
usage() {
  cat <<'EOF'
Usage: install.sh [--minimal | --full] [--skip-packages] [--no-tailscale]
                   [--logi-options]

  --minimal        macOS: headless dev box for SSH / remote Claude Code. Core CLI
                   tools, zsh, vim, Claude Code, Tailscale, Remote Login on, no
                   sleep. Skips GUI apps, fonts, VS Code and iTerm2.
  --full           macOS: everything, including desktop apps (the default).
  --skip-packages  Don't install/upgrade packages; just relink config.
  --no-tailscale   Don't install Tailscale (--tailscale turns it back on).
  --logi-options   macOS: install Logi Options+ on its own and exit; skips
                   everything else. Also included in --full.

On Linux, --minimal/--full/--logi-options are ignored (there's no desktop part).
The chosen options are remembered, so a plain re-run (or `tools-update`) keeps them.
EOF
}

parse_args() {
  MODE="" SKIP_PACKAGES="" NO_TAILSCALE=""
  # Saved options are the defaults; flags given now override them.
  local saved=()
  if [[ -f "$STATE_DIR/args" ]]; then
    read -r -a saved <"$STATE_DIR/args" || true
  elif [[ -f "$STATE_DIR/mode" ]]; then
    saved=("--$(cat "$STATE_DIR/mode")")   # saved by older versions
  fi
  local arg
  for arg in ${saved[@]+"${saved[@]}"} "$@"; do
    case "$arg" in
      --minimal) MODE=minimal ;;
      --full) MODE=full ;;
      --skip-packages|--skip-brew) SKIP_PACKAGES=1 ;;
      --no-tailscale) NO_TAILSCALE=1 ;;
      --tailscale) NO_TAILSCALE="" ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
    esac
  done
  MODE="${MODE:-full}"
  mkdir -p "$STATE_DIR"
  # Remember the mode and tailscale choice; --skip-packages is a one-off.
  echo "--$MODE${NO_TAILSCALE:+ --no-tailscale}" >"$STATE_DIR/args"
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

finish() {
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    bold "Done, with warnings:"
    printf '  - %s\n' "${WARNINGS[@]}"
  else
    bold "Done!"
  fi
  local line
  for line in "$@"; do info "$line"; done
  info "Re-run any time with: tools-update"
}
