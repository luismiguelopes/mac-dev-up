# mac-dev-up: Safe macOS Dev Environment Updater

`mac-dev-up` is a bash script designed to securely, quickly, and reliably keep your macOS development environment up to date.

## Features

- **Safe Mode by Default** — avoids updates in system paths (System Python, System Ruby, global npm) to protect your OS. Smartly detects version managers (`NVM`, `ASDF`, `Pyenv`, `Rbenv`) and safely applies updates within them.
- **Alternative Package Managers** — natively detects and updates global packages via `pnpm` or `yarn` as an alternative to `npm`.
- **Fast Mode (Parallel Execution)** — runs independent tasks concurrently, tracking each background job individually and reporting its exit code.
- **Per-Module Run Summary** — prints a summary at the end of every run showing which modules succeeded, which failed, and how long each one took.
- **Config File Support** — persist your preferences in `~/.mac-dev-up.conf` without passing flags every time.
- **Selective Exclusion** — skip specific modules with `--exclude` even when running `--all`.
- **Verified Auto-Update** — checks for newer versions and verifies the download against a SHA-256 checksum before installing.
- **Smart Tool Installation** — detects if Homebrew is missing and offers to install it on the fly.
- **Sudo Heartbeat** — refreshes `sudo` in the background so you only need to enter your password once.
- **Resilient Internet Check** — validates connectivity before proceeding.
- **Dry-Run Mode** — preview every command that would be executed without touching the system.
- **macOS Native Notifications** — triggers a system notification when the update process completes.
- **LaunchAgent Installer** — generates and registers a native macOS `LaunchAgent` that runs the script silently every Sunday at 10:00 AM, with full output logging.

## Installation

```bash
curl -O https://raw.githubusercontent.com/luismiguelopes/mac-dev-up/main/mac-dev-up.sh
chmod +x mac-dev-up.sh
sudo mv mac-dev-up.sh /usr/local/bin/mac-dev-up
```

## Usage

```bash
mac-dev-up [options]
```

### Update Targets

| Flag | Description |
|---|---|
| `--all` | Run all supported updates (default) |
| `--brew` | Update Homebrew packages and casks |
| `--python` | Update pip, setuptools, and wheel |
| `--npm` | Update global Node packages (falls back to `pnpm` or `yarn` if detected) |
| `--ruby` | Update RubyGems (respects `Rbenv`, `ASDF`, and `mise`) |
| `--macos` | Check and install macOS software updates |
| `--composer` | Update Composer and global packages |
| `--rust` | Update Rust toolchain via `rustup` |
| `--mise` | Update mise itself and all tools it manages |
| `--go` | Update Go toolchain (supports mise, asdf, and brew) |
| `--pipx` | Update all pipx-installed packages via `pipx upgrade-all` |
| `--mas` | Update Mac App Store apps (requires [mas-cli](https://github.com/mas-cli/mas)) |
| `--exclude=LIST` | Skip specific modules, comma-separated (e.g. `--exclude=macos,ruby`) |

### Execution Modes

| Flag | Description |
|---|---|
| `--safe` | Safe mode (default) — skips system directories to prevent breaking macOS |
| `--full` | Aggressive updates — uses `--greedy` in brew to also catch self-updating apps like Chrome |
| `--fast` | Parallel execution for independent tasks |
| `--dry-run` | Preview mode — shows what would run without making any changes |
| `--verbose` | Detailed logs for debugging |
| `--version` | Print the current version and exit |
| `--install-cron` | Install a macOS `LaunchAgent` to run `mac-dev-up` silently every Sunday at 10:00 AM |
| `--uninstall-cron` | Remove the macOS `LaunchAgent` |

### Run Summary

At the end of every run, a per-module summary is printed:

```
== Run Summary ==
✔  brew     — 38s
✔  python   — 6s
⚠  npm      — FAILED (4s)
✔  rust     — 12s
```

## Config File

Create `~/.mac-dev-up.conf` to persist your preferences. CLI flags always take precedence.

```ini
# ~/.mac-dev-up.conf
MODE    = full
FAST    = true
EXCLUDE = macos, ruby
```

| Key | Values | Description |
|---|---|---|
| `MODE` | `safe` \| `full` | Sets the update mode |
| `FAST` | `true` \| `false` | Enables parallel execution |
| `EXCLUDE` | comma-separated module names | Modules to skip on every run |

## Automated Weekly Updates

Run once to install a native macOS LaunchAgent that executes `mac-dev-up` every Sunday at 10:00 AM:

```bash
mac-dev-up --install-cron
```

Logs are written to `~/Library/Logs/mac-dev-up/`:

```
~/Library/Logs/mac-dev-up/run.log   # standard output
~/Library/Logs/mac-dev-up/run.err   # standard error
```

## Integrity Verification

Each release ships a `mac-dev-up.sh.sha256` checksum file. The auto-update mechanism verifies it automatically. To verify manually:

```bash
curl -O https://raw.githubusercontent.com/luismiguelopes/mac-dev-up/main/mac-dev-up.sh.sha256
shasum -a 256 -c mac-dev-up.sh.sha256
```

## Supported Toolchains

| Tool | Version Manager Support |
|---|---|
| Homebrew | — |
| Python / pip | `pyenv`, `asdf`, `mise`, system (safe mode skips) |
| Node.js / npm | `nvm`, `asdf`, `mise`, `pnpm`, `yarn` |
| Ruby / gems | `rbenv`, `asdf`, `mise`, system (SIP-protected, always skipped) |
| Rust | `rustup` |
| PHP / Composer | — |
| macOS | `softwareupdate` |
| mise | — |
| Go | `mise`, `asdf`, `brew` |
| pipx | — |
| Mac App Store | `mas-cli` |

## License

Distributed under the MIT License. See the [LICENSE](LICENSE) file for more details.
