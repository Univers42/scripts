#!/usr/bin/env bash
# ── setup_pyenv.sh ───────────────────────────────────────────────────────────
# Creates a Python virtual-environment in .pyenv/ at the project root and
# installs the pip dependencies needed by the vendor/scripts/ tooling.
#
# Usage (from project root):
#   bash vendor/scripts/setup_pyenv.sh          # create & install
#   source .pyenv/bin/activate                   # activate in current shell
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_DIR="$PROJECT_ROOT/.pyenv"

# ── colors ───────────────────────────────────────────────────────────────────
GREEN='\033[92m'
CYAN='\033[96m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "  ${DIM}→${RESET} %s\n" "$*"; }
ok()    { printf "  ${GREEN}●${RESET} ${BOLD}%s${RESET}\n" "$*"; }

# ── create venv ──────────────────────────────────────────────────────────────
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/python3" ]; then
    info "venv already exists at ${CYAN}.pyenv/${RESET}"
else
    info "creating venv at ${CYAN}.pyenv/${RESET}"
    python3 -m venv "$VENV_DIR"
fi

# ── activate ─────────────────────────────────────────────────────────────────
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# ── upgrade pip silently ─────────────────────────────────────────────────────
info "upgrading pip"
pip install --upgrade pip --quiet 2>/dev/null

# ── install dependencies ─────────────────────────────────────────────────────
DEPS=(cpplint clang-format)

for dep in "${DEPS[@]}"; do
    if pip show "$dep" > /dev/null 2>&1; then
        info "$dep ${DIM}already installed${RESET}"
    else
        info "installing ${CYAN}$dep${RESET}"
        pip install "$dep" --quiet
    fi
done

ok "pyenv ready  →  source .pyenv/bin/activate"
