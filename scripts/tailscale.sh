#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Install Tailscale and bring it up. Idempotent; run standalone or from the
# installers.
#
#   scripts/tailscale.sh            # macOS: menu bar app; Linux: system service
#   scripts/tailscale.sh --minimal  # macOS: headless daemon that runs at boot,
#                                   # no login session or GUI needed
#
# Set TS_AUTHKEY (from https://login.tailscale.com/admin/settings/keys) to join
# the tailnet without the browser login.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TS_APP="/Applications/Tailscale.app"

tailscale_cli() {
  if command -v tailscale >/dev/null; then
    command -v tailscale
  elif [[ -x "$TS_APP/Contents/MacOS/Tailscale" ]]; then
    echo "$TS_APP/Contents/MacOS/Tailscale"
  fi
}

install_tailscale_macos() {
  if [[ "$MODE" == minimal ]]; then
    # The open-source daemon runs as a root LaunchDaemon, so the machine stays
    # on the tailnet after a reboot with nobody logged in.
    if [[ -d "$TS_APP" ]]; then
      info "Tailscale app already installed; leaving it (it only runs while you're logged in)"
      return
    fi
    command -v tailscaled >/dev/null || brew install tailscale </dev/null
    if ! launchctl print system/com.tailscale.tailscaled >/dev/null 2>&1; then
      as_root "$(command -v tailscaled)" install-system-daemon
      info "installed tailscaled as a system daemon"
    fi
  else
    if [[ -d "$TS_APP" ]]; then
      info "Tailscale app already installed"
    else
      brew install --cask tailscale-app </dev/null
    fi
    # Starting the app is what registers its network extension.
    open -g -a Tailscale || true
  fi
}

install_tailscale_linux() {
  if ! command -v tailscale >/dev/null; then
    local script
    script=$(mktemp)
    curl -fsSL https://tailscale.com/install.sh -o "$script"
    as_root sh "$script" </dev/null
    rm -f "$script"
  fi
  if command -v systemctl >/dev/null; then
    as_root systemctl enable --now tailscaled >/dev/null 2>&1 || true
  fi
}

tailscale_up() {
  local cli state
  cli=$(tailscale_cli)
  [[ -n "$cli" ]] || { warn "tailscale CLI not found after install"; return; }
  # The daemon/app can take a moment to start answering.
  for _ in 1 2 3 4 5; do
    state=$("$cli" status --json 2>/dev/null | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p' | head -n1 || true)
    [[ -n "$state" ]] && break
    sleep 2
  done
  if [[ "$state" == Running ]]; then
    info "already connected: $("$cli" ip -4 2>/dev/null | head -n1) ($(hostname -s))"
    return
  fi
  if [[ "$OS" == Darwin && "$MODE" != minimal && -z "${TS_AUTHKEY:-}" ]]; then
    info "sign in from the Tailscale menu bar icon to join your tailnet"
    return
  fi
  bold "Connecting to Tailscale"
  local args=()
  [[ -n "${TS_AUTHKEY:-}" ]] && args+=(--authkey "$TS_AUTHKEY")
  [[ -z "${TS_AUTHKEY:-}" ]] && info "open the login link below to add this machine to your tailnet"
  if [[ "$OS" == Darwin && "$MODE" != minimal ]]; then
    "$cli" up ${args[@]+"${args[@]}"} </dev/null || warn "tailscale up failed"
  else
    as_root "$cli" up ${args[@]+"${args[@]}"} </dev/null || warn "tailscale up failed"
  fi
}

install_tailscale() {
  bold "Installing Tailscale"
  if [[ "$OS" == Darwin ]]; then install_tailscale_macos; else install_tailscale_linux; fi
  tailscale_up
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  parse_args "$@"
  install_tailscale
  finish "Tailscale is set up."
fi
