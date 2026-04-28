# mac-dev-up — Project Guide

## Overview

`mac-dev-up` is a single-file bash script (`mac-dev-up.sh`) that safely updates macOS development environments. It supports Homebrew, Python, Node/npm, Ruby, Rust, Composer, and macOS software updates.

Current version: **1.0.7**

## File Structure

```
mac-dev-up/
├── mac-dev-up.sh         # Main script (only source file)
├── mac-dev-up.sh.sha256  # SHA-256 checksum for integrity verification
├── README.md
└── LICENSE
```

## Key Design Constraints

- **Bash 3.2 compatibility** — macOS ships with bash 3.2. No associative arrays, no `mapfile`, no `declare -A`. Use pipe-delimited strings for structured data (see `SUMMARY_ITEMS`).
- **`set -euo pipefail`** — every command must succeed or be explicitly guarded. Use `|| true` only when failure is genuinely acceptable.
- **No external dependencies** — the script must run with only what macOS provides plus the tools it is updating. No Python helpers, no jq, no third-party CLIs.
- **Safe by default** — `MODE_SAFE=true` is the default. Never touch system paths unless the user explicitly passes `--full`.
- **No eval** — use `bash -c "$*"` inside `run()` to avoid double-expansion.

## Architecture

### Execution Flow

```
load_config → parse args → install_cron? → precheck → check_updates → run_selected → print_summary
```

### Core Helpers

| Function | Purpose |
|---|---|
| `run()` | Executes a command, respects `DRY_RUN` and `VERBOSE` |
| `run_module()` | Wraps a module function, tracks elapsed time and success/failure |
| `record_result()` | Appends to `SUMMARY_ITEMS` (pipe-delimited) |
| `print_summary()` | Parses `SUMMARY_ITEMS` and prints the final table |
| `is_excluded()` | Returns 0 if a module name is in `EXCLUDE_LIST` |
| `load_config()` | Reads `~/.mac-dev-up.conf` and sets defaults |
| `check_updates()` | Fetches remote VERSION, prompts user, verifies SHA-256 before installing |

### Modules

Each module is a function named `update_<name>()` and registered in `run_selected()`:

| Function | Flag | Notes |
|---|---|---|
| `update_brew()` | `--brew` | Offers to install Homebrew if missing; respects `--full` for `--greedy` casks |
| `update_python()` | `--python` | Skips system Python (safe mode), Homebrew-managed Python (PEP 668), and any `EXTERNALLY-MANAGED` env |
| `update_npm()` | `--npm` | Detects NVM / ASDF / pnpm / yarn; skips system prefix in safe mode |
| `update_ruby()` | `--ruby` | Skips SIP-protected system Ruby; respects rbenv / asdf |
| `update_rust()` | `--rust` | Runs `rustup update` |
| `update_composer()` | `--composer` | `composer global update` only in full mode |
| `update_macos()` | `--macos` | Skipped during cron runs (requires interactive sudo) |
| `update_mise()` | `--mise` | Runs `mise self-update` then `mise upgrade` (all managed tools); runs in foreground in fast mode because it modifies shims used by background jobs |
| `update_go()` | `--go` | Detects mise/asdf/brew-managed Go; only mise triggers an actual upgrade — brew defers to the brew module, asdf warns, standalone warns |

### Fast Mode

`--fast` runs `macos` and `brew` in the foreground (sequential, due to sudo/brew locks), then launches all other modules as background jobs. Each job writes to a temp file; PIDs are collected and waited on individually so exit codes are captured. Logs are printed in launch order after all jobs complete.

### LaunchAgent

`--install-cron` writes a plist to `~/Library/LaunchAgents/com.luismiguelopes.mac-dev-up.plist` and loads it with `launchctl`. The agent runs every Sunday at 10:00 AM with `--cron --fast`. Logs go to `~/Library/Logs/mac-dev-up/`.

## Adding a New Module

1. Write `update_<name>()` following the same pattern: guard with `command -v`, respect `MODE_SAFE`, use `run()` for every command.
2. Add `DO_<NAME>=false` to the defaults block at the top.
3. Add `--<name>)  DO_<NAME>=true; RUN_ALL=false ;;` to the arg parser.
4. Add `--<name>` to the `--help` output.
5. Add `DO_<NAME>=true` inside the `if [ "$RUN_ALL" = true ]` block in `run_selected()`.
6. Register the module in both the sequential and fast-mode branches of `run_selected()`.

## Releasing a New Version

1. Update `VERSION="x.y.z"` at the top of `mac-dev-up.sh`.
2. Regenerate the checksum: `shasum -a 256 mac-dev-up.sh > mac-dev-up.sh.sha256`
3. Commit both files together.
4. Push to `main` — the auto-update mechanism fetches directly from `main`.

## Testing

There is no automated test suite. Use dry-run mode for safe iteration:

```bash
bash mac-dev-up.sh --dry-run --verbose --all
bash mac-dev-up.sh --dry-run --fast --exclude=macos,ruby
```

For module-level testing, call the function directly in a subshell after sourcing:

```bash
DRY_RUN=true VERBOSE=true bash -c 'source mac-dev-up.sh; update_python'
```

## Config File Reference

`~/.mac-dev-up.conf` — loaded before CLI flags, so flags always win.

```ini
MODE    = safe | full
FAST    = true | false
EXCLUDE = macos, ruby
```

## Style Rules

- No comments explaining what the code does — only explain non-obvious constraints or workarounds.
- Use `warn` for non-fatal issues, `error` for fatal exits, `log` for section headers, `success` for confirmations.
- Wrap every external command in `run()` — never call `brew`, `pip`, `npm`, etc. directly.
- Keep module functions self-contained. No shared mutable state between modules.
- No AI assistant attribution in commits, comments, or documentation.
