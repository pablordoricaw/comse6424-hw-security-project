# Scripts

This directory contains utility scripts to help with the development, environment setup, and testing of the project.

## Execution

All scripts are intended to be executed from the root of the project repository unless otherwise specified in their help message.

For Bash scripts, ensure each script is executable before running it:

```bash
chmod +x scripts/<script_name>.sh
```

## Script Requirements & Conventions

To maintain consistency and reliability, anyone adding or modifying scripts in this directory should adhere to the following standards:

### 1. Self-Documenting Help Message

Every script must have a usage message invoked with the `-h` or `--help` flags. This message must explain:

* The script's purpose
* Required and optional arguments
* Prerequisites or network requirements (e.g., VPN access)
* Expected side-effects (e.g., files created, sessions launched)

### 2. Strict Execution Mode

Bash scripts must fail fast to prevent silent errors or unintended operations. Always begin Bash scripts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

* `-e`: Exit immediately if a command fails.
* `-u`: Treat unset variables as an error.
* `-o pipefail`: Return the exit status of the last command in the pipe that failed.

### 3. Standardized Output

* **Errors and Warnings:** Must be redirected to standard error (`>&2`) and ideally use clear prefixes (e.g., `[Error]:`, `[Warning]:`).
  - **Color Formatting (Optional but preferred):** To improve readability, use ANSI escape codes for terminal output. For example, print errors in red and warnings in yellow:
    ```bash
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color

    echo -e "❌ ${RED}[Error]:${NC} Message goes here" >&2
    ```
* **Exit Codes:**
  - Use `exit 0` for successful execution and
  - Standard POSIX non-zero exit codes (e.g., `exit 1`) for failures.

### 4. Dependency Checks

If a script relies on external system packages (e.g., `jq`, `curl`, `tmux`, `nc`), it should either document these in the help message or gracefully fail and alert the user if the commands are not found on their machine.
