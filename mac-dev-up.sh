#!/usr/bin/env bash

# ==============================================================================
# mac-dev-up: Safe macOS Dev Environment Updater
# Version: 1.0.1
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

VERSION="1.0.1"
REPO_URL="https://raw.githubusercontent.com/luismiguelopes/mac-dev-up/main/mac-dev-up.sh"

# -------------------- CONFIG DEFAULTS --------------------
MODE_SAFE=true
MODE_FAST=false
DRY_RUN=false
VERBOSE=false

RUN_ALL=true
DO_BREW=false
DO_PYTHON=false
DO_NPM=false
DO_RUBY=false
DO_MACOS=false
DO_COMPOSER=false

# -------------------- COLORS --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}== $* ==${NC}"; }
success() { echo -e "${GREEN}✔ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
error() { echo -e "${RED}✖ $*${NC}"; exit 1; }

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] $*"
  else
    [ "$VERBOSE" = true ] && echo "[RUN] $*"
    eval "$@"
  fi
}

# -------------------- AUTO-UPDATE --------------------
check_updates() {
  log "Checking for script updates..."
  REMOTE_VERSION=$(curl -s "$REPO_URL" | grep "VERSION=" | head -1 | cut -d'"' -f2 || echo "$VERSION")
  
  if [ "$REMOTE_VERSION" != "$VERSION" ] && [ "$REMOTE_VERSION" != "" ]; then
    warn "New version available: $REMOTE_VERSION (Current: $VERSION)"
    read -p "Do you want to update mac-dev-up? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      sudo curl -L "$REPO_URL" -o "$(which mac-dev-up)"
      success "Updated to $REMOTE_VERSION! Please restart the script."
      exit 0
    fi
  else
    success "mac-dev-up is up to date."
  fi
}

# -------------------- ARG PARSER --------------------
for arg in "$@"; do
  case $arg in
    --all) RUN_ALL=true ;;
    --brew) DO_BREW=true; RUN_ALL=false ;;
    --python) DO_PYTHON=true; RUN_ALL=false ;;
    --npm) DO_NPM=true; RUN_ALL=false ;;
    --ruby) DO_RUBY=true; RUN_ALL=false ;;
    --macos) DO_MACOS=true; RUN_ALL=false ;;
    --composer) DO_COMPOSER=true; RUN_ALL=false ;;
    --safe) MODE_SAFE=true ;;
    --full) MODE_SAFE=false ;;
    --fast) MODE_FAST=true ;;
    --dry-run) DRY_RUN=true ;;
    --verbose) VERBOSE=true ;;
    --help)
      echo "Usage: mac-dev-up [options]"
      echo ""
      echo "--all         Run all updates (default)"
      echo "--brew        Update Homebrew"
      echo "--python      Update Python packages"
      echo "--npm         Update npm global"
      echo "--ruby        Update Ruby gems"
      echo "--macos       Update macOS"
      echo "--composer    Update Composer"
      echo ""
      echo "--safe        Safe mode (default)"
      echo "--full        Aggressive updates"
      echo "--fast        Parallel execution"
      echo "--dry-run     Preview only"
      echo "--verbose     Debug logs"
      exit 0
      ;;
    *) error "Unknown option: $arg" ;;
  esac
done

# -------------------- PRECHECK --------------------
log "Pre-checks (v$VERSION)"

# Resilient Internet Check
if ! curl -sfI https://1.1.1.1 > /dev/null && ! curl -sfI https://github.com > /dev/null; then
  error "No internet connection detected."
fi

check_updates

if ! sudo -v; then
  error "Sudo permissions required to run updates."
fi

# Better Sudo Heartbeat
( while true; do sudo -n true; sleep 60; done ) &
SUDO_PID=$!
trap 'kill $SUDO_PID 2>/dev/null' EXIT

# -------------------- MODULES --------------------

update_macos() {
  log "macOS Software Update"
  run "sudo softwareupdate --install --all"
}

update_brew() {
  BREW_CMD="brew"

  if ! command -v brew >/dev/null; then
    warn "Homebrew not found."
    read -p "Do you want to install Homebrew? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      log "Installing Homebrew..."
      run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      if [ "$DRY_RUN" = true ]; then
        return
      fi
      if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        BREW_CMD="/opt/homebrew/bin/brew"
      elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        BREW_CMD="/usr/local/bin/brew"
      fi
    else
      warn "Skipping Homebrew update."
      return
    fi
  fi

  log "Homebrew update"
  run "$BREW_CMD update"
  run "$BREW_CMD upgrade"

  if [ "$MODE_SAFE" = false ]; then
    log "Brew Casks (Aggressive)"
    run "$BREW_CMD upgrade --cask --greedy || true"
  else
    log "Brew Casks (Safe)"
    run "$BREW_CMD upgrade --cask || true"
  fi

  run "$BREW_CMD cleanup"
}

update_python() {
  if ! command -v python3 >/dev/null; then return; fi
  
  PY_PATH=$(which python3)
  if [[ "$PY_PATH" == "/usr/bin/"* ]] && [ "$MODE_SAFE" = true ]; then
    warn "System Python detected. Skipping to avoid permission issues (Safe Mode)."
    return
  fi

  log "Python (pip) update"
  run "python3 -m pip install --upgrade pip setuptools wheel"
}

update_npm() {
  if ! command -v npm >/dev/null; then return; fi

  PREFIX=$(npm config get prefix)
  if [ "$MODE_SAFE" = true ]; then
    warn "Skipping npm global updates (Safe Mode)."
    return
  fi

  if [[ "$PREFIX" == "/usr/local"* ]]; then
    warn "npm global in system path. Might require sudo. Skipping for safety."
    return
  fi

  log "npm global update"
  run "npm update -g"
}

update_ruby() {
  if ! command -v gem >/dev/null; then return; fi

  GEM_PATH=$(which gem)
  if [[ "$GEM_PATH" == "/usr/bin/"* ]]; then
    warn "System Ruby detected (SIP Protected). Skipping."
    return
  fi

  if [ "$MODE_SAFE" = true ]; then
    warn "Skipping Ruby gems (Safe Mode)."
    return
  fi

  log "RubyGems update"
  run "gem update --system"
  run "gem update"
}

update_composer() {
  if ! command -v composer >/dev/null; then return; fi
  log "Composer update"
  run "composer self-update"
  [ "$MODE_SAFE" = false ] && run "composer global update"
}

# -------------------- EXECUTION --------------------
run_selected() {
  if [ "$RUN_ALL" = true ]; then
    DO_BREW=true; DO_PYTHON=true; DO_NPM=true; DO_RUBY=true; DO_MACOS=true; DO_COMPOSER=true
  fi

  if [ "$MODE_FAST" = true ]; then
    warn "Fast mode enabled. Grouping outputs and respecting system locks."
    TMP_DIR=$(mktemp -d)
    
    # Foreground tasks (avoid input/lock collisions)
    [ "$DO_MACOS" = true ] && update_macos
    [ "$DO_BREW" = true ] && update_brew

    # Background tasks (safe to parallelize)
    [ "$DO_COMPOSER" = true ] && { log "Composer (bg)"; update_composer > "$TMP_DIR/composer.log" 2>&1; } &
    [ "$DO_PYTHON" = true ] && { log "Python (bg)"; update_python > "$TMP_DIR/python.log" 2>&1; } &
    [ "$DO_NPM" = true ] && { log "npm (bg)"; update_npm > "$TMP_DIR/npm.log" 2>&1; } &
    [ "$DO_RUBY" = true ] && { log "Ruby (bg)"; update_ruby > "$TMP_DIR/ruby.log" 2>&1; } &
    
    wait
    
    # Print background logs
    for f in "$TMP_DIR"/*.log; do
      if [ -f "$f" ]; then
        echo -e "\n${BLUE}=== $(basename "$f" .log) ===${NC}"
        cat "$f"
      fi
    done
    rm -rf "$TMP_DIR"
  else
    [ "$DO_MACOS" = true ] && update_macos
    [ "$DO_BREW" = true ] && update_brew
    [ "$DO_COMPOSER" = true ] && update_composer
    [ "$DO_PYTHON" = true ] && update_python
    [ "$DO_NPM" = true ] && update_npm
    [ "$DO_RUBY" = true ] && update_ruby
  fi
}

# -------------------- RUN --------------------
START=$(date +%s)
run_selected
END=$(date +%s)

success "Environment updated successfully in $((END - START))s"