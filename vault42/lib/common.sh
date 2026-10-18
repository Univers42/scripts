# shellcheck shell=bash
# common.sh — the messages and small formatters every vault42 module shares. Sourced; sets no
# shell options. Messages go to stderr so stdout stays the command's data.
#
# Exit codes (the contract callers branch on): 0 ok · 1 failed or refused · 2 usage or invalid
# config · 3 pushed to the PERSONAL vault · 4 locked by another run · 5 a credential is missing.

note() { printf '[vault42] %s\n' "$*" >&2; }

# usage_error TEXT: prints the usage line and returns the usage status.
usage_error() {
  note "usage: $*"
  return 2
}

is_uint() {
  case "${1:-}" in
  '' | *[!0-9]*) return 1 ;;
  esac
}

# human_bytes N: 1536 -> "1.5 KiB".
human_bytes() {
  awk -v b="$1" 'BEGIN { split("B KiB MiB GiB TiB", u, " "); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ } printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i] }'
}

# free_mb DIR: free megabytes at the nearest existing ancestor of DIR.
free_mb() {
  local dir="$1"
  while [ ! -d "$dir" ]; do dir="$(dirname "$dir")"; done
  df -Pm "$dir" | awk 'NR == 2 { print $4 }'
}

# count_lines TEXT: the number of non-empty lines, 0 for the empty string.
count_lines() { grep -c . <<<"$1" || true; }

# space_guard DIR BYTES FLOOR_MB: status 1 unless BYTES fit at DIR while FLOOR_MB stays free.
space_guard() {
  local dir="$1" bytes="$2" floor="$3" free
  free="$(free_mb "$dir")"
  [ "$bytes" -le $(((free - floor) * 1048576)) ] && return 0
  note "need $(human_bytes "$bytes") at $dir but only $free MB is free and $floor MB is kept back; free space first"
  return 1
}
