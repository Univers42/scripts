#!/usr/bin/env bash
# Fetch SonarCloud analysis details for a branch into local JSON and TXT reports.
#
# Run from anywhere inside track-binocle:
#   bash vendor/scripts/sonarcloud_fetch_branch.sh
#
# Token discovery order:
#   1. Existing SONAR_TOK environment variable
#   2. Existing SONAR_TOKEN environment variable
#   3. First SONAR_TOK=... entry found in .env, .env.local, *.env, or *.env.local
#      below the repository root, excluding .git, node_modules, dist, and build dirs.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly DEFAULT_BRANCH="main"
readonly DEFAULT_HOST="https://sonarcloud.io"
readonly DEFAULT_OUT_DIR="$ROOT_DIR/audit/sonar"
readonly DEFAULT_PROJECT_KEY="Univers42_osionos"
readonly DEFAULT_ORGANIZATION="univers42"

BRANCH="${SONAR_BRANCH:-$DEFAULT_BRANCH}"
HOST="${SONAR_HOST_URL:-$DEFAULT_HOST}"
OUT_DIR="${SONAR_OUT_DIR:-$DEFAULT_OUT_DIR}"
PROJECT_KEY="${SONAR_PROJECT_KEY:-}"
PROJECT_DIR="${SONAR_PROJECT_DIR:-}"
ORGANIZATION="${SONAR_ORGANIZATION:-}"
RUN_SCANNER="${RUN_SONAR_SCANNER:-auto}"
PER_PAGE="${SONAR_PAGE_SIZE:-500}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --branch NAME        SonarCloud branch to fetch (default: $DEFAULT_BRANCH)
  --project-key KEY    SonarCloud project key. If omitted, read from sonar-project.properties.
  --project-dir DIR    Directory that contains sonar-project.properties.
  --organization KEY   SonarCloud organization key (default: $DEFAULT_ORGANIZATION)
  --out-dir DIR        Output directory (default: audit/sonar below repo root)
  --host URL           Sonar host URL (default: $DEFAULT_HOST)
  --scan               Run sonar-scanner before fetching results.
  --no-scan            Skip sonar-scanner and fetch latest published results only.
  --help               Show this help.

Environment:
  SONAR_TOK            Preferred auth token variable.
  SONAR_TOKEN          Fallback auth token variable.
  RUN_SONAR_SCANNER    auto | 1 | 0 (default: auto)

Outputs:
  audit/sonar/<project-key>/<branch>/issues-all.json
  audit/sonar/<project-key>/<branch>/hotspots-all.json
  audit/sonar/<project-key>/<branch>/quality-gate.json
  audit/sonar/<project-key>/<branch>/measures.json
  audit/sonar/<project-key>/<branch>/summary.txt
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      BRANCH="${2:?Missing value for --branch}"
      shift 2
      ;;
    --project-key)
      PROJECT_KEY="${2:?Missing value for --project-key}"
      shift 2
      ;;
    --project-dir)
      PROJECT_DIR="${2:?Missing value for --project-dir}"
      shift 2
      ;;
    --organization)
      ORGANIZATION="${2:?Missing value for --organization}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:?Missing value for --out-dir}"
      shift 2
      ;;
    --host)
      HOST="${2:?Missing value for --host}"
      shift 2
      ;;
    --scan)
      RUN_SCANNER="1"
      shift
      ;;
    --no-scan)
      RUN_SCANNER="0"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

trim_quotes() {
  local value="$1"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s' "$value"
}

find_env_token() {
  if [[ -n "${SONAR_TOK:-}" ]]; then
    printf '%s' "$SONAR_TOK"
    return 0
  fi

  if [[ -n "${SONAR_TOKEN:-}" ]]; then
    printf '%s' "$SONAR_TOKEN"
    return 0
  fi

  local env_file line value
  while IFS= read -r -d '' env_file; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line#export }"
      [[ "$line" =~ ^[[:space:]]*SONAR_TOK[[:space:]]*= ]] || continue
      value="${line#*=}"
      value="${value%%#*}"
      value="$(trim_quotes "${value//[[:space:]]/}")"
      if [[ -n "$value" ]]; then
        printf '%s' "$value"
        return 0
      fi
    done < "$env_file"
  done < <(
    find "$ROOT_DIR" \
      \( -path '*/.git' -o -path '*/node_modules' -o -path '*/dist' -o -path '*/build' -o -path '*/coverage' \) -prune \
      -o -type f \( -name '.env' -o -name '.env.local' -o -name '*.env' -o -name '*.env.local' \) -print0
  )

  return 1
}

find_project_file() {
  if [[ -n "$PROJECT_DIR" ]]; then
    local configured_file="$PROJECT_DIR/sonar-project.properties"
    [[ -f "$configured_file" ]] || {
      return 1
    }
    printf '%s' "$configured_file"
    return 0
  fi

  local project_file
  project_file="$(find "$ROOT_DIR" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/dist' -o -path '*/build' -o -path '*/coverage' \) -prune \
    -o -type f -name 'sonar-project.properties' -print | sort | head -n 1)"

  if [[ -z "$project_file" ]]; then
    return 1
  fi

  printf '%s' "$project_file"
}

read_property() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file"
}

api_get() {
  local path="$1"
  local url="$HOST$path"
  if [[ -n "${TOKEN:-}" ]]; then
    curl -fsS -u "$TOKEN:" "$url"
  else
    curl -fsS "$url"
  fi
}

fetch_paginated() {
  local path="$1"
  local array_key="$2"
  local out_file="$3"
  local page=1
  local total=0
  local fetched=0
  local tmp_file
  tmp_file="$(mktemp)"
  echo '[]' > "$out_file"

  while true; do
    local separator='&'
    [[ "$path" == *'?'* ]] || separator='?'

    api_get "${path}${separator}ps=${PER_PAGE}&p=${page}" > "$tmp_file"
    total="$(jq -r '.total // .paging.total // 0' "$tmp_file")"
    local count
    count="$(jq -r --arg key "$array_key" '.[$key] // [] | length' "$tmp_file")"

    jq --arg key "$array_key" '.[$key] // []' "$tmp_file" \
      | jq -s '.[0] + .[1]' "$out_file" - > "$out_file.tmp"
    mv "$out_file.tmp" "$out_file"

    fetched="$(jq 'length' "$out_file")"
    printf '  %s page %s: %s item(s), %s/%s fetched\n' "$array_key" "$page" "$count" "$fetched" "$total"

    [[ "$count" -eq 0 || "$fetched" -ge "$total" ]] && break
    page=$((page + 1))
  done

  rm -f "$tmp_file"
}

keep_open_issues() {
  local issues_file="$1"
  jq '
    [
      .[]
      | select((.resolution // "") == "")
      | select((.status // .issueStatus // "") as $status
        | $status == "OPEN" or $status == "CONFIRMED" or $status == "REOPENED")
    ]
  ' "$issues_file" > "$issues_file.tmp"
  mv "$issues_file.tmp" "$issues_file"
}

keep_hotspots_to_review() {
  local hotspots_file="$1"
  jq '[.[] | select((.status // "") == "TO_REVIEW")]' "$hotspots_file" > "$hotspots_file.tmp"
  mv "$hotspots_file.tmp" "$hotspots_file"
}

wait_for_ce_task() {
  local report_file="$PROJECT_DIR/.scannerwork/report-task.txt"
  if [[ ! -f "$report_file" ]]; then
    return 0
  fi

  local ce_task_id
  ce_task_id="$(awk -F= '$1 == "ceTaskId" { print $2; exit }' "$report_file")"
  if [[ -z "$ce_task_id" ]]; then
    return 0
  fi

  echo "Waiting for SonarCloud to process analysis task $ce_task_id..."
  local attempt status
  for attempt in $(seq 1 60); do
    status="$(api_get "/api/ce/task?id=$ce_task_id" | jq -r '.task.status // "UNKNOWN"')"
    case "$status" in
      SUCCESS)
        echo "SonarCloud processing complete."
        return 0
        ;;
      FAILED|CANCELED)
        echo "SonarCloud processing ended with status: $status" >&2
        return 1
        ;;
      *)
        sleep 2
        ;;
    esac
  done

  echo "Timed out waiting for SonarCloud processing." >&2
  return 1
}

run_scanner_if_requested() {
  if [[ "$RUN_SCANNER" == "0" || "$RUN_SCANNER" == "false" ]]; then
    echo "Skipping sonar-scanner; fetching latest published SonarCloud results."
    return 0
  fi

  if [[ -z "${TOKEN:-}" ]]; then
    if [[ "$RUN_SCANNER" == "1" || "$RUN_SCANNER" == "true" ]]; then
      echo "sonar-scanner requires SONAR_TOK or SONAR_TOKEN." >&2
      exit 1
    fi
    echo "No token found; skipping sonar-scanner and fetching public SonarCloud results."
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    if [[ "$RUN_SCANNER" == "1" || "$RUN_SCANNER" == "true" ]]; then
      echo "sonar-scanner requires Docker for this project." >&2
      exit 1
    fi
    echo "Docker not found; fetching latest published SonarCloud results."
    return 0
  fi

  local scanner_image="${SONAR_SCANNER_IMAGE:-sonarsource/sonar-scanner-cli}"
  local git_mount=()
  local project_mount=()
  local scannerwork_mount=()
  local container_project_dir="/usr/src"
  local super_worktree=""
  super_worktree="$(git -C "$PROJECT_DIR" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -n "$super_worktree" && -d "$super_worktree/.git" ]]; then
    local relative_project_dir
    relative_project_dir="$(realpath --relative-to="$super_worktree" "$PROJECT_DIR")"
    container_project_dir="/$relative_project_dir"
    git_mount=(-v "$super_worktree/.git:/.git:ro")
  fi
  project_mount=(-v "$PROJECT_DIR:$container_project_dir")
  mkdir -p "$PROJECT_DIR/.scannerwork"
  scannerwork_mount=(-v "$PROJECT_DIR/.scannerwork:/tmp/.scannerwork")

  local scanner_args=(
    "-Dsonar.host.url=$HOST"
    "-Dsonar.projectKey=$PROJECT_KEY"
    "-Dsonar.organization=$ORGANIZATION"
  )

  if [[ -n "$BRANCH" && "$BRANCH" != "$DEFAULT_BRANCH" ]]; then
    scanner_args+=("-Dsonar.branch.name=$BRANCH")
  fi

  echo "Running sonar-scanner for branch '$BRANCH' from $PROJECT_DIR..."
  docker run --rm \
    -e SONAR_HOST_URL="$HOST" \
    -e SONAR_TOKEN="$TOKEN" \
    "${project_mount[@]}" \
    "${git_mount[@]}" \
    "${scannerwork_mount[@]}" \
    -w "$container_project_dir" \
    "$scanner_image" \
    "${scanner_args[@]}"

  wait_for_ce_task
}

write_summary() {
  local summary_file="$1"
  local issues_file="$2"
  local hotspots_file="$3"
  local quality_file="$4"
  local measures_file="$5"

  {
    echo "══════════════════════════════════════════════════"
    echo " SonarCloud Branch Audit"
    echo " Project : $PROJECT_KEY"
    echo " Branch  : $BRANCH"
    echo " Host    : $HOST"
    echo " Generated: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
    echo "══════════════════════════════════════════════════"
    echo ""

    echo "Quality Gate"
    jq -r '.projectStatus.status // "UNKNOWN"' "$quality_file" | sed 's/^/  Status: /'
    echo ""

    echo "Measures"
    jq -r '.component.measures[]? | "  \(.metric): \(.value // "n/a")"' "$measures_file"
    echo ""

    echo "Open Issues By Severity"
    for severity in BLOCKER CRITICAL MAJOR MINOR INFO; do
      local count
      count="$(jq --arg severity "$severity" '[.[] | select(.severity == $severity)] | length' "$issues_file")"
      printf '  %-10s %s\n' "$severity" "$count"
    done
    echo ""

    echo "Open Issues By Type"
    for type in BUG VULNERABILITY CODE_SMELL SECURITY_HOTSPOT; do
      local count
      count="$(jq --arg type "$type" '[.[] | select(.type == $type)] | length' "$issues_file")"
      printf '  %-18s %s\n' "$type" "$count"
    done
    echo ""

    echo "Security Hotspots"
    printf '  %-18s %s\n' "TO_REVIEW" "$(jq 'length' "$hotspots_file")"
    echo ""

    echo "Detailed Issues"
    jq -r '
      .[] |
      "[\(.severity)] \(.type) \(.component | split(":")[-1]):\(.line // "?") \(.rule) — \(.message)"
    ' "$issues_file" | sort || true
    echo ""

    echo "Detailed Security Hotspots"
    jq -r '
      .[] |
      "[HOTSPOT] \(.component | split(":")[-1]):\(.line // "?") \(.securityCategory // "unknown") — \(.message)"
    ' "$hotspots_file" | sort || true
  } > "$summary_file"
}

main() {
  require_cmd curl
  require_cmd jq

  TOKEN="$(find_env_token)" || TOKEN=""

  local project_file=""
  project_file="$(find_project_file)" || project_file=""
  if [[ -n "$project_file" ]]; then
    PROJECT_DIR="$(cd "$(dirname "$project_file")" && pwd)"
  else
    PROJECT_DIR="${PROJECT_DIR:-$ROOT_DIR}"
  fi

  if [[ -z "$PROJECT_KEY" && -n "$project_file" ]]; then
    PROJECT_KEY="$(read_property "$project_file" 'sonar.projectKey')"
  fi

  if [[ -z "$ORGANIZATION" && -n "$project_file" ]]; then
    ORGANIZATION="$(read_property "$project_file" 'sonar.organization')"
  fi

  PROJECT_KEY="${PROJECT_KEY:-$DEFAULT_PROJECT_KEY}"
  ORGANIZATION="${ORGANIZATION:-$DEFAULT_ORGANIZATION}"

  local safe_project safe_branch branch_out_dir
  safe_project="${PROJECT_KEY//[^A-Za-z0-9_.-]/_}"
  safe_branch="${BRANCH//[^A-Za-z0-9_.-]/_}"
  branch_out_dir="$OUT_DIR/$safe_project/$safe_branch"
  mkdir -p "$branch_out_dir"

  echo "Root       : $ROOT_DIR"
  echo "Project dir: $PROJECT_DIR"
  echo "Project key: $PROJECT_KEY"
  echo "Organization: $ORGANIZATION"
  echo "Branch     : $BRANCH"
  echo "Output     : $branch_out_dir"

  run_scanner_if_requested

  local encoded_project encoded_branch
  encoded_project="$(jq -rn --arg value "$PROJECT_KEY" '$value|@uri')"
  encoded_branch="$(jq -rn --arg value "$BRANCH" '$value|@uri')"

  local issues_file="$branch_out_dir/issues-all.json"
  local hotspots_file="$branch_out_dir/hotspots-all.json"
  local quality_file="$branch_out_dir/quality-gate.json"
  local measures_file="$branch_out_dir/measures.json"
  local components_file="$branch_out_dir/components.json"
  local summary_file="$branch_out_dir/summary.txt"

  echo "Fetching SonarCloud issues..."
  fetch_paginated "/api/issues/search?componentKeys=$encoded_project&branch=$encoded_branch&resolved=false&statuses=OPEN,CONFIRMED,REOPENED&additionalFields=_all" "issues" "$issues_file"
  keep_open_issues "$issues_file"

  echo "Fetching SonarCloud security hotspots..."
  fetch_paginated "/api/hotspots/search?projectKey=$encoded_project&branch=$encoded_branch&status=TO_REVIEW" "hotspots" "$hotspots_file"
  keep_hotspots_to_review "$hotspots_file"

  echo "Fetching quality gate..."
  api_get "/api/qualitygates/project_status?projectKey=$encoded_project&branch=$encoded_branch" | jq '.' > "$quality_file"

  echo "Fetching measures..."
  api_get "/api/measures/component?component=$encoded_project&branch=$encoded_branch&metricKeys=bugs,vulnerabilities,code_smells,security_hotspots,coverage,duplicated_lines_density,ncloc" | jq '.' > "$measures_file"

  echo "Fetching component tree..."
  api_get "/api/components/tree?component=$encoded_project&branch=$encoded_branch&qualifiers=FIL&ps=500" | jq '.' > "$components_file"

  write_summary "$summary_file" "$issues_file" "$hotspots_file" "$quality_file" "$measures_file"

  local issue_count hotspot_count gate_status
  issue_count="$(jq 'length' "$issues_file")"
  hotspot_count="$(jq 'length' "$hotspots_file")"
  gate_status="$(jq -r '.projectStatus.status // "UNKNOWN"' "$quality_file")"

  echo ""
  echo "Artifacts written:"
  echo "  $issues_file"
  echo "  $hotspots_file"
  echo "  $quality_file"
  echo "  $measures_file"
  echo "  $components_file"
  echo "  $summary_file"
  echo ""
  echo "Quality gate: $gate_status"
  echo "Open issues: $issue_count"
  echo "Security hotspots to review: $hotspot_count"
}

main "$@"