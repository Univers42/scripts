#!/usr/bin/env bash
# setup-pdf.sh — Install all dependencies for both md-to-pdf.py and md-to-pdf.mjs
# Usage: bash setup-pdf.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   PDF Generator — Setup (Python + Node)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Which engines do you want? ────────────────────────────────────────────────
INSTALL_PYTHON=true
INSTALL_NODE=true

for arg in "$@"; do
  case "$arg" in
    --python-only) INSTALL_NODE=false ;;
    --node-only)   INSTALL_PYTHON=false ;;
  esac
done

# ── 1. System dependencies (WeasyPrint needs pango + cairo) ──────────────────
if $INSTALL_PYTHON; then
  echo ""
  echo "  [1/4] System dependencies for WeasyPrint…"

  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
      python3 python3-pip python3-venv \
      libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 \
      libgdk-pixbuf-2.0-0 libffi-dev libcairo2 \
      libgirepository1.0-dev gir1.2-pango-1.0 \
      fonts-dejavu-core fonts-liberation fonts-noto \
      2>/dev/null
  elif command -v brew &>/dev/null; then
    brew install python3 pango libffi gdk-pixbuf cairo
  else
    echo "  ⚠  Unsupported package manager. Install pango + cairo manually."
    echo "     See: https://doc.courtbouillon.org/weasyprint/stable/first_steps.html"
  fi
  echo "  ✓  System dependencies ready"
fi

# ── 2. Python venv ────────────────────────────────────────────────────────────
if $INSTALL_PYTHON; then
  echo ""
  echo "  [2/4] Python virtual environment…"

  VENV="$SCRIPT_DIR/.venv-pdf"
  python3 -m venv "$VENV"
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  pip install --upgrade pip -q
  pip install markdown pymdown-extensions weasyprint requests -q
  deactivate

  echo "  ✓  Python venv ready at .venv-pdf/"
fi

# ── 3. Node.js dependencies ───────────────────────────────────────────────────
if $INSTALL_NODE; then
  echo ""
  echo "  [3/4] Node.js dependencies…"

  if ! command -v node &>/dev/null; then
    echo "  ✗  Node.js not found. Install from https://nodejs.org or via nvm."
    INSTALL_NODE=false
  else
    echo "  Node $(node --version) found"
    cd "$SCRIPT_DIR"
    # Create package.json if missing
    if [[ ! -f package.json ]]; then
      echo '{"type":"module","private":true}' > package.json
    fi
    npm install --save-dev puppeteer marked 2>&1 | grep -E "(added|error|warn)" || true
    echo "  ✓  Node dependencies ready (puppeteer + marked)"
  fi
fi

# ── 4. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "  [4/4] Verifying installation…"

if $INSTALL_PYTHON && [[ -f "$SCRIPT_DIR/.venv-pdf/bin/python3" ]]; then
  "$SCRIPT_DIR/.venv-pdf/bin/python3" - <<'PYCHECK'
import markdown, weasyprint, requests
print(f"  ✓  Python: markdown={markdown.version}  weasyprint={weasyprint.__version__}  requests={requests.__version__}")
PYCHECK
fi

if $INSTALL_NODE && command -v node &>/dev/null && [[ -d "$SCRIPT_DIR/node_modules/puppeteer" ]]; then
  node -e "
    const p = require('./node_modules/puppeteer/package.json');
    const m = require('./node_modules/marked/package.json');
    console.log('  ✓  Node: puppeteer=' + p.version + '  marked=' + m.version);
  " 2>/dev/null || echo "  ✓  Node modules present"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Setup complete! Usage:"
echo ""
echo "  Python (WeasyPrint — diagrams via Kroki API):"
echo "    source .venv-pdf/bin/activate"
echo "    python3 md-to-pdf.py README.md"
echo "    python3 md-to-pdf.py README.md --author 'Your Name'"
echo ""
echo "  Node (Puppeteer — diagrams rendered natively in browser):"
echo "    node md-to-pdf.mjs README.md"
echo "    node md-to-pdf.mjs README.md --author 'Your Name' --debug-html"
echo ""
echo "  Quick wrapper (auto-selects best engine):"
echo "    ./convert.sh README.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
