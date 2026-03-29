# mac-dev-up: Safe macOS Dev Environment Updater

`mac-dev-up` is a bash script designed to securely, quickly, and reliably keep your macOS development environment up to date.

## 🚀 Features

- **Safe Mode by Default:** Avoids updates in system paths (System Python, System Ruby, global npm) to protect your OS. It smartly detects localized version managers (`NVM`, `ASDF`, `Pyenv`, `Rbenv`) and safely applies updates within them.
- **Alternative Package Managers:** Natively detects and updates global packages via `pnpm` and `yarn` as an alternative to `npm`.
- **Fast Mode (Parallel Execution):** Runs independent tasks concurrently to save time.
- **Auto-Update:** Automatically checks for newer versions in the GitHub repository and updates itself.
- **Smart Tool Installation:** Detects if essential tools (like Homebrew) are missing and offers to install them on the fly.
- **Sudo Heartbeat:** Pings `sudo` in the background so you only need to enter your password once at the start.
- **Resilient Internet Check:** Validates internet connectivity before proceeding.
- **Dry-run Mode:** Allows you to preview the commands that would be executed without modifying the system.

## 📦 Installation

You can install or update the script by downloading it directly from the repository:

```bash
curl -O https://raw.githubusercontent.com/luismiguelopes/mac-dev-up/main/mac-dev-up.sh
chmod +x mac-dev-up.sh
sudo mv mac-dev-up.sh /usr/local/bin/mac-dev-up
```



## 🛠 Usage

Run the script in your terminal:

```bash
mac-dev-up [options]
```

### Update Options
- `--all`         Run all supported updates (default behavior).
- `--brew`        Update Homebrew packages and casks.
- `--python`      Update Python packages (pip, setuptools, wheel).
- `--npm`         Update global npm packages (automatically falls back to `pnpm` or `yarn` if detected).
- `--ruby`        Update RubyGems (respects `Rbenv` and `ASDF`).
- `--macos`       Check and install macOS software updates.
- `--composer`    Update Composer globally.
- `--rust`        Update Rust toolchain via `rustup`.

### Execution Modes
- `--safe`        Safe mode (default). Skips system directories to prevent breaking macOS.
- `--full`        Aggressive updates (e.g., uses `--greedy` flag in brew to catch tools like Google Chrome which self-update).
- `--fast`        Parallel execution for independent tasks.
- `--dry-run`     Preview mode (only shows what would be executed).
- `--verbose`     Displays detailed logs for debugging.

## 📝 License

Distributed under the MIT License. See the [LICENSE](LICENSE) file for more details.
