#!/usr/bin/env bash

# ==============================================================================
# mac-dev-up: Safe macOS Dev Environment Updater
# Version: 1.0.5
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

VERSION="1.0.5"
REPO_URL="https://raw.githubusercontent.com/luismiguelopes/mac-dev-up/main/mac-dev-up.sh"
CHECKSUM_URL="https://raw.githubusercontent.com/luismiguelopes/mac-dev-up/main/mac-dev-up.sh.sha256"

# -------------------- ENVIRONMENT RECOVERY --------------------
# Ensures tools like brew, nvm, and asdf are found when run via LaunchAgent.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.asdf/shims:$HOME/.asdf/bin:$HOME/.pyenv/shims:$HOME/.pyenv/bin:$HOME/.rbenv/shims:$HOME/.rbenv/bin:$HOME/.cargo/bin:$PATH"
[ -d "$HOME/.nvm" ] && export NVM_DIR="$HOME/.nvm"

# -------------------- CONFIG DEFAULTS --------------------
MODE_SAFE=true
MODE_FAST=false
DRY_RUN=false
VERBOSE=false
INSTALL_CRON=false
IS_CRON_RUN=false
EXCLUDE_LIST=""

RUN_ALL=true
DO_BREW=false
DO_PYTHON=false
DO_NPM=false
DO_RUBY=false
DO_MACOS=false
DO_COMPOSER=false
DO_RUST=false

# -------------------- COLORS --------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}== $* ==${NC}"; }
success() { echo -e "${GREEN}✔ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠ $*${NC}"; }
error()   { echo -e "${RED}✖ $*${NC}"; exit 1; }

# Uses bash -c in an isolated subshell instead of eval to avoid double-expansion
# and limit the blast radius of any unexpected input.
run() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] $*"
  else
    [ "$VERBOSE" = true ] && echo "[RUN] $*"
    bash -c "$*"
  fi
}

# -------------------- CONFIG FILE --------------------
# Reads ~/.mac-dev-up.conf and applies settings as defaults.
# Command-line arguments (parsed after this) always take precedence.
# Supported keys: MODE (safe|full), FAST (true|false), EXCLUDE (comma-separated modules)
load_config() {
  local config_file="$HOME/.mac-dev-up.conf"
  [ -f "$config_file" ] || return 0

  log "Loading config from $config_file"
  while IFS='=' read -r key value; do
    # Skip comments and blank lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${key//[[:space:]]/}" ]] && continue
    key="${key//[[:space:]]/}"
    value="${value//[[:space:]]/}"
    case "$key" in
      MODE)
        [[ "$value" == "safe" ]] && MODE_SAFE=true
        [[ "$value" == "full" ]] && MODE_SAFE=false
        ;;
      FAST)
        [[ "$value" == "true" ]] && MODE_FAST=true
        ;;
      EXCLUDE)
        EXCLUDE_LIST="$value"
        ;;
    esac
  done < "$config_file"
}

# -------------------- EXCLUDE HELPER --------------------
is_excluded() {
  local module="$1" item
  local IFS=','
  for item in $EXCLUDE_LIST; do
    item="${item//[[:space:]]/}"
    [ "$item" = "$module" ] && return 0
  done
  return 1
}

# -------------------- SUMMARY TRACKING --------------------
# Uses a pipe-delimited string for bash 3.2 compatibility (no associative arrays).
SUMMARY_ITEMS=""

record_result() {
  local name="$1" status="$2" elapsed="$3"
  SUMMARY_ITEMS="${SUMMARY_ITEMS}|${name}:${status}:${elapsed}"
}

print_summary() {
  echo ""
  log "Run Summary"
  local IFS='|' item name rest status elapsed
  for item in $SUMMARY_ITEMS; do
    [ -z "$item" ] && continue
    name="${item%%:*}"
    rest="${item#*:}"
    status="${rest%%:*}"
    elapsed="${rest#*:}"
    if [ "$status" = "ok" ]; then
      success "  $name — ${elapsed}"
    else
      warn "  $name — FAILED (${elapsed})"
    fi
  done
}

# Wraps a module function to track its success/failure and elapsed time.
# Safe under set -e because the module call is inside an if-condition.
run_module() {
  local name="$1" func="$2" start elapsed
  start=$(date +%s)
  if "$func"; then
    elapsed=$(( $(date +%s) - start ))
    record_result "$name" "ok" "${elapsed}s"
  else
    elapsed=$(( $(date +%s) - start ))
    record_result "$name" "failed" "${elapsed}s"
    warn "Module '$name' encountered errors — continuing."
  fi
}

# -------------------- AUTO-UPDATE --------------------
check_updates() {
  if [ "$IS_CRON_RUN" = true ]; then return; fi
  log "Checking for script updates..."

  local remote_version
  remote_version=$(curl -sf "$REPO_URL" | grep '^VERSION=' | head -1 | cut -d'"' -f2 || echo "$VERSION")

  if [ "$remote_version" != "$VERSION" ] && [ -n "$remote_version" ]; then
    warn "New version available: $remote_version (Current: $VERSION)"
    read -p "Do you want to update mac-dev-up? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      local tmp_script tmp_checksum install_path
      tmp_script=$(mktemp)
      tmp_checksum=$(mktemp)

      log "Downloading new version..."
      if ! curl -sfL "$REPO_URL" -o "$tmp_script"; then
        warn "Download failed. Aborting update."
        rm -f "$tmp_script" "$tmp_checksum"
        return
      fi

      # Integrity check: verify SHA-256 against published checksum file.
      # To publish: run `shasum -a 256 mac-dev-up.sh > mac-dev-up.sh.sha256` and commit it.
      log "Verifying integrity..."
      if curl -sfL "$CHECKSUM_URL" -o "$tmp_checksum" 2>/dev/null; then
        local expected actual
        expected=$(awk '{print $1}' "$tmp_checksum")
        actual=$(shasum -a 256 "$tmp_script" | awk '{print $1}')
        if [ "$expected" != "$actual" ]; then
          warn "Checksum mismatch — aborting update for safety."
          warn "  expected: $expected"
          warn "  got:      $actual"
          rm -f "$tmp_script" "$tmp_checksum"
          return
        fi
        success "Integrity verified."
      else
        warn "Checksum file not found at remote — skipping integrity check."
      fi

      install_path=$(command -v mac-dev-up || echo "/usr/local/bin/mac-dev-up")
      sudo cp "$tmp_script" "$install_path"
      sudo chmod +x "$install_path"
      rm -f "$tmp_script" "$tmp_checksum"

      success "Updated to $remote_version! Please restart the script."
      exit 0
    fi
  else
    success "mac-dev-up is up to date."
  fi
}

# -------------------- CONFIG + ARG PARSER --------------------
# Load config first so command-line flags can override it.
load_config

for arg in "$@"; do
  case $arg in
    --install-cron) INSTALL_CRON=true ;;
    --cron)         IS_CRON_RUN=true; RUN_ALL=true ;;
    --all)          RUN_ALL=true ;;
    --brew)         DO_BREW=true;     RUN_ALL=false ;;
    --python)       DO_PYTHON=true;   RUN_ALL=false ;;
    --npm)          DO_NPM=true;      RUN_ALL=false ;;
    --ruby)         DO_RUBY=true;     RUN_ALL=false ;;
    --macos)        DO_MACOS=true;    RUN_ALL=false ;;
    --composer)     DO_COMPOSER=true; RUN_ALL=false ;;
    --rust)         DO_RUST=true;     RUN_ALL=false ;;
    --safe)         MODE_SAFE=true ;;
    --full)         MODE_SAFE=false ;;
    --fast)         MODE_FAST=true ;;
    --dry-run)      DRY_RUN=true ;;
    --verbose)      VERBOSE=true ;;
    --exclude=*)    EXCLUDE_LIST="${arg#--exclude=}" ;;
    --help)
      echo "Usage: mac-dev-up [options]"
      echo ""
      echo "Update targets:"
      echo "  --all              Run all updates (default)"
      echo "  --brew             Update Homebrew"
      echo "  --python           Update Python packages"
      echo "  --npm              Update npm global"
      echo "  --ruby             Update Ruby gems"
      echo "  --macos            Update macOS"
      echo "  --composer         Update Composer"
      echo "  --rust             Update Rust toolchain"
      echo "  --exclude=LIST     Skip modules (comma-separated, e.g. --exclude=macos,ruby)"
      echo ""
      echo "Execution modes:"
      echo "  --safe             Safe mode (default)"
      echo "  --full             Aggressive updates"
      echo "  --fast             Parallel execution"
      echo "  --dry-run          Preview only"
      echo "  --verbose          Debug logs"
      echo "  --install-cron     Install macOS LaunchAgent (Sundays 10:00 AM)"
      echo ""
      echo "Config file: ~/.mac-dev-up.conf"
      echo "  MODE=safe|full"
      echo "  FAST=true|false"
      echo "  EXCLUDE=module1,module2"
      exit 0
      ;;
    *) error "Unknown option: $arg" ;;
  esac
done

# -------------------- CRON INSTALLER --------------------
install_cron() {
  log "Installing macOS LaunchAgent for automated weekly updates (Sun 10:00 AM)..."

  local plist_dir="$HOME/Library/LaunchAgents"
  local plist_file="$plist_dir/com.luismiguelopes.mac-dev-up.plist"
  local script_path log_dir
  script_path=$(command -v mac-dev-up || echo "/usr/local/bin/mac-dev-up")
  log_dir="$HOME/Library/Logs/mac-dev-up"

  mkdir -p "$plist_dir" "$log_dir"

  cat <<EOF > "$plist_file"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.luismiguelopes.mac-dev-up</string>
    <key>ProgramArguments</key>
    <array>
        <string>$script_path</string>
        <string>--cron</string>
        <string>--fast</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>
        <key>Hour</key>
        <integer>10</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$log_dir/run.log</string>
    <key>StandardErrorPath</key>
    <string>$log_dir/run.err</string>
</dict>
</plist>
EOF

  launchctl unload "$plist_file" 2>/dev/null || true
  launchctl load "$plist_file"

  success "LaunchAgent installed at $plist_file"
  success "Cron logs will be written to $log_dir/"
  success "mac-dev-up will now run automatically every Sunday at 10:00 AM."
  exit 0
}

if [ "$INSTALL_CRON" = true ]; then
  install_cron
fi

# -------------------- PRECHECK --------------------
if [ "$IS_CRON_RUN" = false ]; then
  log "Pre-checks (v$VERSION)"
else
  log "Silent Cron Run (v$VERSION)"
fi

# Resilient Internet Check
if ! curl -sfI https://1.1.1.1 > /dev/null && ! curl -sfI https://github.com > /dev/null; then
  error "No internet connection detected."
fi

check_updates

if [ "$IS_CRON_RUN" = false ]; then
  if ! sudo -v; then
    error "Sudo permissions required to run updates."
  fi

  # Sudo Heartbeat — refresh sudo token in the background so it never expires mid-run.
  ( while true; do sudo -n true; sleep 60; done ) &
  SUDO_PID=$!
  trap 'kill $SUDO_PID 2>/dev/null' EXIT
fi

# -------------------- MODULES --------------------

update_macos() {
  if [ "$IS_CRON_RUN" = true ]; then
    warn "Skipping macOS update during silent cron run (requires sudo)."
    return
  fi
  log "macOS Software Update"
  run "sudo softwareupdate --install --all"
}

update_brew() {
  local brew_cmd="brew"

  if ! command -v brew >/dev/null; then
    warn "Homebrew not found."
    read -p "Do you want to install Homebrew? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      log "Installing Homebrew..."
      run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      if [ "$DRY_RUN" = true ]; then return; fi
      if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        brew_cmd="/opt/homebrew/bin/brew"
      elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        brew_cmd="/usr/local/bin/brew"
      fi
    else
      warn "Skipping Homebrew update."
      return
    fi
  fi

  log "Homebrew update"
  run "$brew_cmd update"
  run "$brew_cmd upgrade"

  if [ "$MODE_SAFE" = false ]; then
    log "Brew Casks (Aggressive)"
    run "$brew_cmd upgrade --cask --greedy || true"
  else
    log "Brew Casks (Safe)"
    run "$brew_cmd upgrade --cask || true"
  fi

  run "$brew_cmd cleanup"
}

update_python() {
  if ! command -v python3 >/dev/null; then return; fi

  local py_path
  py_path=$(which python3)

  if command -v pyenv >/dev/null && [[ "$py_path" == *"/pyenv/"* || "$py_path" == *".pyenv"* ]]; then
    log "Pyenv Python detected"
  elif command -v asdf >/dev/null && [[ "$py_path" == *"/asdf/"* || "$py_path" == *".asdf"* ]]; then
    log "ASDF Python detected"
  elif [[ "$py_path" == "/usr/bin/"* ]] && [ "$MODE_SAFE" = true ]; then
    warn "System Python detected. Skipping to avoid permission issues (Safe Mode)."
    return
  fi

  log "Python (pip) update"
  run "python3 -m pip install --upgrade pip setuptools wheel"
}

update_npm() {
  # Node Version Managers — update npm itself first
  if [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
    log "NVM detected. Updating npm for current Node version"
    run "source \"$NVM_DIR/nvm.sh\" && npm install -g npm"
  elif command -v asdf >/dev/null && asdf current nodejs >/dev/null 2>&1; then
    log "ASDF Node.js detected. Updating npm"
    run "npm install -g npm"
  fi

  # Package managers (pnpm > yarn > npm)
  if command -v pnpm >/dev/null; then
    log "pnpm global update"
    run "pnpm update -g"
  elif command -v yarn >/dev/null; then
    log "yarn global update"
    run "yarn global upgrade"
  elif command -v npm >/dev/null; then
    local prefix
    prefix=$(npm config get prefix)

    if [[ "$prefix" == "/usr/local"* ]] || [[ "$prefix" == "/usr/bin"* ]]; then
      warn "npm global prefix is a system path. Skipping for safety."
      return
    fi

    if [ "$MODE_SAFE" = true ] && [[ "$prefix" != *".nvm"* ]] && [[ "$prefix" != *".asdf"* ]]; then
      warn "Skipping npm global packages update (Safe Mode)."
      return
    fi

    log "npm global update"
    run "npm update -g"
  fi
}

update_ruby() {
  if ! command -v gem >/dev/null; then return; fi

  local gem_path
  gem_path=$(which gem)

  if command -v rbenv >/dev/null && [[ "$gem_path" == *"/rbenv/"* || "$gem_path" == *".rbenv"* ]]; then
    log "Rbenv Ruby detected"
  elif command -v asdf >/dev/null && [[ "$gem_path" == *"/asdf/"* || "$gem_path" == *".asdf"* ]]; then
    log "ASDF Ruby detected"
  elif [[ "$gem_path" == "/usr/bin/"* ]]; then
    warn "System Ruby detected (SIP Protected). Skipping."
    return
  fi

  if [ "$MODE_SAFE" = true ] && \
     [[ "$gem_path" != *"/rbenv/"* ]] && [[ "$gem_path" != *"/asdf/"* ]] && \
     [[ "$gem_path" != *".rbenv"* ]] && [[ "$gem_path" != *".asdf"* ]]; then
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
  if [ "$MODE_SAFE" = false ]; then
    run "composer global update"
  fi
}

update_rust() {
  if ! command -v rustup >/dev/null; then return; fi
  log "Rustup toolchain update"
  run "rustup update"
}

# -------------------- EXECUTION --------------------
run_selected() {
  if [ "$RUN_ALL" = true ]; then
    DO_BREW=true; DO_PYTHON=true; DO_NPM=true; DO_RUBY=true
    DO_MACOS=true; DO_COMPOSER=true; DO_RUST=true
  fi

  if [ "$MODE_FAST" = true ]; then
    warn "Fast mode enabled. Foreground: macos, brew. Background: everything else."
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # Foreground — must run sequentially (sudo, brew locks)
    [ "$DO_MACOS" = true ]    && ! is_excluded "macos" && run_module "macos" update_macos
    [ "$DO_BREW"  = true ]    && ! is_excluded "brew"  && run_module "brew"  update_brew

    # Background — safe to parallelise; collect PIDs to check exit codes individually
    local bg_pids=() bg_names=()
    if [ "$DO_COMPOSER" = true ] && ! is_excluded "composer"; then
      update_composer > "$tmp_dir/composer.log" 2>&1 & bg_pids+=($!); bg_names+=("composer")
    fi
    if [ "$DO_PYTHON" = true ] && ! is_excluded "python"; then
      update_python   > "$tmp_dir/python.log"   2>&1 & bg_pids+=($!); bg_names+=("python")
    fi
    if [ "$DO_NPM" = true ] && ! is_excluded "npm"; then
      update_npm      > "$tmp_dir/npm.log"      2>&1 & bg_pids+=($!); bg_names+=("npm")
    fi
    if [ "$DO_RUBY" = true ] && ! is_excluded "ruby"; then
      update_ruby     > "$tmp_dir/ruby.log"     2>&1 & bg_pids+=($!); bg_names+=("ruby")
    fi
    if [ "$DO_RUST" = true ] && ! is_excluded "rust"; then
      update_rust     > "$tmp_dir/rust.log"     2>&1 & bg_pids+=($!); bg_names+=("rust")
    fi

    # Collect results and print logs in launch order
    local i
    for i in "${!bg_pids[@]}"; do
      local name="${bg_names[$i]}" status="ok"
      wait "${bg_pids[$i]}" || status="failed"
      record_result "$name" "$status" "bg"
      echo -e "\n${BLUE}=== $name ===${NC}"
      cat "$tmp_dir/${name}.log" 2>/dev/null || true
    done
    rm -rf "$tmp_dir"
  else
    [ "$DO_MACOS" = true ]    && ! is_excluded "macos"    && run_module "macos"    update_macos
    [ "$DO_BREW" = true ]     && ! is_excluded "brew"     && run_module "brew"     update_brew
    [ "$DO_COMPOSER" = true ] && ! is_excluded "composer" && run_module "composer" update_composer
    [ "$DO_PYTHON" = true ]   && ! is_excluded "python"   && run_module "python"   update_python
    [ "$DO_NPM" = true ]      && ! is_excluded "npm"      && run_module "npm"      update_npm
    [ "$DO_RUBY" = true ]     && ! is_excluded "ruby"     && run_module "ruby"     update_ruby
    [ "$DO_RUST" = true ]     && ! is_excluded "rust"     && run_module "rust"     update_rust
  fi
}

# -------------------- RUN --------------------
START=$(date +%s)
run_selected
TOTAL=$(( $(date +%s) - START ))

print_summary
success "Environment updated in ${TOTAL}s"

if [ "$DRY_RUN" = false ]; then
  osascript -e 'display notification "All updates completed successfully!" with title "mac-dev-up"'
fi
