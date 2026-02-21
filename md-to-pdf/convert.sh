#!/usr/bin/env bash
# convert.sh — Smart wrapper: converts any Markdown file to PDF.
# Auto-selects the best available engine:
#   1. Node/Puppeteer  (preferred — renders Mermaid natively in browser)
#   2. Python/WeasyPrint (fallback — uses Kroki.io API for Mermaid)
#
# Usage:
#   ./convert.sh README.md
#   ./convert.sh README.md output.pdf
#   ./convert.sh README.md --author "Your Name" --no-cover
#   ./convert.sh README.md --engine python     # Force Python
#   ./convert.sh README.md --engine node       # Force Node
#   ./convert.sh --help
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; NC='\033[0m'

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  echo ""
  echo "  Usage: ./convert.sh <input.md> [output.pdf] [options]"
  echo ""
  echo "  Options:"
  echo "    --title    \"...\"   Override document title"
  echo "    --subtitle \"...\"   Override document subtitle"
  echo "    --author   \"...\"   Author name for cover page"
  echo "    --no-cover         Skip cover page"
  echo "    --no-cache         Force re-render all Mermaid diagrams (Python only)"
  echo "    --debug-html       Also save the intermediate HTML file"
  echo "    --engine node      Force Node/Puppeteer engine"
  echo "    --engine python    Force Python/WeasyPrint engine"
  echo "    --help             Show this message"
  echo ""
}

if [[ $# -eq 0 ]] || [[ "${1:-}" == "--help" ]]; then
  usage; exit 0
fi

# ── Parse args ────────────────────────────────────────────────────────────────
INPUT=""
OUTPUT=""
PASS_ARGS=()
FORCE_ENGINE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)  FORCE_ENGINE="$2"; shift 2 ;;
    --help)    usage; exit 0 ;;
    --title|--subtitle|--author)
               PASS_ARGS+=("$1" "$2"); shift 2 ;;
    --no-cover|--no-cache|--debug-html)
               PASS_ARGS+=("$1"); shift ;;
    -*)        echo -e "${RED}✗${NC}  Unknown option: $1"; usage; exit 1 ;;
    *)
      if [[ -z "$INPUT" ]]; then
        INPUT="$1"
      elif [[ -z "$OUTPUT" ]]; then
        OUTPUT="$1"
      fi
      shift ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  echo -e "${RED}✗${NC}  No input file specified."
  usage; exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo -e "${RED}✗${NC}  File not found: $INPUT"
  exit 1
fi

# Default output path
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="${INPUT%.md}.pdf"
fi

# ── Detect available engines ──────────────────────────────────────────────────
HAS_NODE=false
HAS_PYTHON=false

if command -v node &>/dev/null && [[ -d "$SCRIPT_DIR/node_modules/puppeteer" ]]; then
  HAS_NODE=true
fi

VENV="$SCRIPT_DIR/.venv-pdf"
if [[ -f "$VENV/bin/python3" ]]; then
  HAS_PYTHON=true
fi

# ── Select engine ─────────────────────────────────────────────────────────────
ENGINE=""
case "${FORCE_ENGINE:-}" in
  node)
    if $HAS_NODE; then ENGINE="node"
    else echo -e "${RED}✗${NC}  Node engine requested but not available. Run: bash setup-pdf.sh --node-only"; exit 1; fi
    ;;
  python)
    if $HAS_PYTHON; then ENGINE="python"
    else echo -e "${RED}✗${NC}  Python engine requested but not available. Run: bash setup-pdf.sh --python-only"; exit 1; fi
    ;;
  "")
    # Auto-select: prefer Node (native Mermaid)
    if $HAS_NODE; then ENGINE="node"
    elif $HAS_PYTHON; then ENGINE="python"
    else
      echo -e "${RED}✗${NC}  No PDF engine found!"
      echo "   Run: bash setup-pdf.sh"
      exit 1
    fi
    ;;
  *)
    echo -e "${RED}✗${NC}  Unknown engine: $FORCE_ENGINE (use 'node' or 'python')"
    exit 1
    ;;
esac

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}   Markdown → PDF Converter                       ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Engine  : ${GREEN}$ENGINE${NC}"
echo -e "  Input   : $INPUT"
echo -e "  Output  : $OUTPUT"
[[ ${#PASS_ARGS[@]} -gt 0 ]] && echo -e "  Options : ${PASS_ARGS[*]}"
echo ""

# ── Run ───────────────────────────────────────────────────────────────────────
START=$(date +%s)

if [[ "$ENGINE" == "node" ]]; then
  node "$SCRIPT_DIR/md-to-pdf.mjs" "$INPUT" "$OUTPUT" "${PASS_ARGS[@]}"
else
  source "$VENV/bin/activate"
  python3 "$SCRIPT_DIR/md-to-pdf.py" "$INPUT" "$OUTPUT" "${PASS_ARGS[@]}"
  deactivate
fi

END=$(date +%s)
ELAPSED=$((END - START))

echo ""
echo -e "${BLUE}──────────────────────────────────────────────────${NC}"
if [[ -f "$OUTPUT" ]]; then
  SIZE=$(du -h "$OUTPUT" | cut -f1)
  echo -e "  ${GREEN}✓${NC}  PDF ready: $OUTPUT  ($SIZE, ${ELAPSED}s)"
else
  echo -e "  ${RED}✗${NC}  PDF generation failed"
  exit 1
fi
echo -e "${BLUE}──────────────────────────────────────────────────${NC}"
echo ""
