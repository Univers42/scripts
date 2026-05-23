#!/usr/bin/env bash
set -euo pipefail

# ─── Load .env if present (next to this script) ───────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
    set +a
fi

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Mirror all GitHub repos from a user account and/or org(s) to a local directory.
Credentials are resolved in order: CLI flags → .env file → shell environment.

Options:
  -u, --user   USER   GitHub username         (env: GITHUB_USER)
  -o, --org    ORGS   Org name(s), comma-sep  (env: GITHUB_ORG)
  -d, --dir    DIR    Backup root directory   (env: BACKUP_DIR)
  -h, --help          Show this help

Authentication:
  The script uses 'gh' CLI auth. Run 'gh auth login' once before the first run.
  Alternatively set GITHUB_TOKEN in .env to skip interactive auth.

Examples:
  $(basename "$0") --user LESdylan --org Univers42 --dir /mnt/backups/github
  $(basename "$0")                              # uses .env defaults
EOF
    exit 0
}

# ─── Parse CLI flags (override .env) ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--user)  GITHUB_USER="${2:?'--user requires a value'}"; shift 2 ;;
        -o|--org)   GITHUB_ORG="${2:?'--org requires a value'}";  shift 2 ;;
        -d|--dir)   BACKUP_DIR="${2:?'--dir requires a value'}";  shift 2 ;;
        -h|--help)  usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

# ─── Defaults ─────────────────────────────────────────────────────────────────
GITHUB_USER="${GITHUB_USER:-}"
GITHUB_ORG="${GITHUB_ORG:-}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/github-backups}"
LOG_FILE="${LOG_FILE:-$BACKUP_DIR/backup.log}"

# ─── Preflight checks ─────────────────────────────────────────────────────────
if [[ -z "$GITHUB_USER" && -z "$GITHUB_ORG" ]]; then
    echo "Error: set GITHUB_USER and/or GITHUB_ORG (in .env or via --user/--org)." >&2
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: 'gh' CLI not found. Install: sudo apt install gh" >&2
    exit 1
fi

if ! command -v git &>/dev/null; then
    echo "Error: 'git' not found." >&2
    exit 1
fi

# Auth: honour GITHUB_TOKEN if set, otherwise rely on existing gh session
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export GH_TOKEN="$GITHUB_TOKEN"
fi

if ! gh auth status &>/dev/null; then
    echo "Error: gh CLI is not authenticated. Run: gh auth login" >&2
    exit 1
fi

if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    echo "Error: cannot create BACKUP_DIR '$BACKUP_DIR'. Is the disk mounted?" >&2
    exit 1
fi

# ─── Logging ──────────────────────────────────────────────────────────────────
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

# ─── Core backup function ─────────────────────────────────────────────────────
backup_repos() {
    local ENTITY="$1"

    log "── Fetching repo list: $ENTITY"

    local REPOS
    if ! REPOS=$(gh repo list "$ENTITY" --limit 1000 --json sshUrl -q '.[].sshUrl' 2>>"$LOG_FILE"); then
        log "ERROR: could not list repos for '$ENTITY' (check access rights)"
        return 1
    fi

    if [[ -z "$REPOS" ]]; then
        log "   No repos found for $ENTITY"
        return 0
    fi

    local TARGET_BASE="$BACKUP_DIR/$ENTITY"
    mkdir -p "$TARGET_BASE"

    local ok=0 fail=0
    while IFS= read -r REPO_URL; do
        [[ -z "$REPO_URL" ]] && continue
        local REPO_NAME TARGET_DIR
        REPO_NAME=$(basename "$REPO_URL" .git)
        TARGET_DIR="$TARGET_BASE/${REPO_NAME}.git"

        if [[ -d "$TARGET_DIR/HEAD" ]]; then
            log "   update  $REPO_NAME"
            if git -C "$TARGET_DIR" remote update --prune >>"$LOG_FILE" 2>&1; then
                (( ok++ ))
            else
                log "   WARN: update failed — $REPO_NAME"
                (( fail++ ))
            fi
        else
            log "   clone   $REPO_NAME"
            if git clone --mirror "$REPO_URL" "$TARGET_DIR" >>"$LOG_FILE" 2>&1; then
                (( ok++ ))
            else
                log "   WARN: clone failed — $REPO_NAME"
                (( fail++ ))
            fi
        fi
    done <<< "$REPOS"

    log "   done: $ok ok, $fail failed"
}

# ─── Run ──────────────────────────────────────────────────────────────────────
log "═══════════════════════════════════════════════"
log "GitHub backup started"
log "  BACKUP_DIR  : $BACKUP_DIR"
log "  GITHUB_USER : ${GITHUB_USER:-<not set>}"
log "  GITHUB_ORG  : ${GITHUB_ORG:-<not set>}"
log "  gh identity : $(gh api user -q '.login' 2>/dev/null || echo 'unknown')"
log "═══════════════════════════════════════════════"

[[ -n "$GITHUB_USER" ]] && backup_repos "$GITHUB_USER"

if [[ -n "$GITHUB_ORG" ]]; then
    IFS=',' read -ra ORGS <<< "$GITHUB_ORG"
    for ORG in "${ORGS[@]}"; do
        ORG="${ORG//[[:space:]]/}"
        [[ -n "$ORG" ]] && backup_repos "$ORG"
    done
fi

log "GitHub backup finished"
log ""
