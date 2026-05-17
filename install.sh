#!/usr/bin/env bash
# spoofdpi-turkey installer.
#
# Bootstraps a stock macOS system with the prerequisites and deploys the
# spoofdpi-tr wrapper to /usr/local/bin. Idempotent across re-invocations.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/atakanapan/spoofdpi-turkey/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/atakanapan/spoofdpi-turkey/main/install.sh | bash -s -- --yes
#
# Options:
#   -y, --yes    Assume affirmative response to all prompts (non-interactive).

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/atakanapan/spoofdpi-turkey/main"
SCRIPT_URL="$REPO_RAW/spoofdpi-tr"
INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="$INSTALL_DIR/spoofdpi-tr"
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
  esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
err()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; }
info() { printf '\033[34m==>\033[0m %s\n' "$*"; }

# When invoked via `curl ... | bash`, stdin is the pipe; interactive prompts
# must read from /dev/tty directly.
confirm() {
  local prompt="$1" answer
  if [[ "$ASSUME_YES" == "1" ]]; then return 0; fi
  if [[ -t 0 ]]; then
    printf "%s [Y/n] " "$prompt"
    read -r answer
  elif [[ -r /dev/tty ]]; then
    printf "%s [Y/n] " "$prompt" > /dev/tty
    read -r answer < /dev/tty
  else
    err "no interactive terminal available; pass --yes for non-interactive installation"
    err "  curl ... | bash -s -- --yes"
    exit 1
  fi
  case "$answer" in
    [Yy]|[Yy][Ee][Ss]|"") return 0 ;;
    *) return 1 ;;
  esac
}

# Platform gate.
if [[ "$(uname)" != "Darwin" ]]; then
  err "this installer supports macOS only; see README.md for manual installation"
  exit 1
fi

# Homebrew bootstrap. If absent, prompt the user and run the official
# installer in non-interactive mode. The xcode-select prerequisite is
# handled by Homebrew's installer itself.
if ! command -v brew >/dev/null 2>&1; then
  info "Homebrew is required but not installed."
  echo ""
  echo "The following actions will be performed:"
  echo "  1. Apple Command Line Tools will be installed if absent (system dialog may appear)"
  echo "  2. Homebrew will be installed via the official installer (https://brew.sh)"
  echo "  3. The Homebrew shell environment will be appended to ~/.zprofile"
  echo ""
  if ! confirm "Proceed?"; then
    info "aborted; install Homebrew manually from https://brew.sh and re-run this installer"
    exit 1
  fi

  info "installing Homebrew (administrator password may be requested)..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Resolve the Homebrew prefix depending on architecture.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW_BIN="/usr/local/bin/brew"
  else
    err "Homebrew installation appears to have failed; brew binary not found"
    exit 1
  fi

  # Activate Homebrew for the current shell session.
  eval "$("$BREW_BIN" shellenv)"

  # Persist the shellenv invocation in ~/.zprofile for future sessions.
  ZPROFILE="$HOME/.zprofile"
  if [[ ! -f "$ZPROFILE" ]] || ! grep -Fq "$BREW_BIN shellenv" "$ZPROFILE"; then
    {
      echo ""
      echo "# Homebrew (added by spoofdpi-turkey installer)"
      echo "eval \"\$($BREW_BIN shellenv)\""
    } >> "$ZPROFILE"
    info "appended Homebrew shellenv to $ZPROFILE"
  fi
fi

# SpoofDPI installation.
if ! command -v spoofdpi >/dev/null 2>&1; then
  info "installing SpoofDPI via Homebrew"
  brew install spoofdpi
fi

# Wrapper deployment.
info "deploying wrapper to $INSTALL_PATH (administrator privileges required)"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -fsSL "$SCRIPT_URL" -o "$TMP"

# Sanity check on the downloaded file.
if ! head -1 "$TMP" | grep -q '^#!.*bash'; then
  err "downloaded file does not appear to be a bash script; installation aborted"
  exit 1
fi

sudo mkdir -p "$INSTALL_DIR"
sudo install -m 0755 "$TMP" "$INSTALL_PATH"

# PATH advisory.
if ! echo ":$PATH:" | grep -q ":$INSTALL_DIR:"; then
  echo ""
  err "$INSTALL_DIR is not in PATH; append the following line to ~/.zshrc:"
  echo "    export PATH=\"$INSTALL_DIR:\$PATH\""
fi

echo ""
bold "Installation complete."
echo ""
echo "Usage:"
echo "    spoofdpi-tr"
echo ""
echo "An administrator password will be requested on first invocation."
echo "Terminate with Ctrl+C; the system proxy configuration will be reverted automatically."
