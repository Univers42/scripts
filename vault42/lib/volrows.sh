# shellcheck shell=bash
# volrows.sh — the data-volume table behind `vault42 volumes`. Sourced; sets no shell options; needs
# volumes.sh, seedsums.sh and common.sh, and VOL_ROOT set to the volumes target's root.
#
#   _vol_rows         "NAME<TAB>BYTES<TAB>USERS<TAB>STATE" per data volume; STATE is "archived DATE" or
#                     "missing", judged from the names SHA256SUMS lists and the archive's presence
#   _vol_print_rows   the same rows, aligned, from stdin
#
# Caveat: sizes come from `docker system df -v`, which prints three significant digits in decimal
# units (off by up to ~0.5%), and a volume it does not list shows 0 bytes.

_vol_sizes() {
  docker system df -v 2>/dev/null | awk '
    function bytes(s,   n, u) {
      n = s + 0; u = s; sub(/^[0-9.]+/, "", u)
      return n * (u == "kB" ? 1e3 : u == "MB" ? 1e6 : u == "GB" ? 1e9 : u == "TB" ? 1e12 : 1)
    }
    /^Local Volumes space usage:/ { on = 1; next }
    on && /^VOLUME NAME/ { rows = 1; next }
    rows && NF == 0 { exit }
    rows { printf "%s\t%.0f\n", $1, bytes($NF) }'
}

# "NAME<TAB>BYTES<TAB>USERS<TAB>STATE"; STATE is "archived DATE" or "missing", judged from the names
# SHA256SUMS lists and the archive's presence (no hashing).
_vol_rows() {
  local sizes name size users base state sums="$VOL_ROOT/secrets/SHA256SUMS"
  docker info >/dev/null 2>&1 || {
    note "docker is not reachable; start it, then rerun"
    return 1
  }
  sizes="$(_vol_sizes)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    size="$(awk -F'\t' -v n="$name" '$1 == n { print $2 }' <<<"$sizes")"
    users="$(volume_users "$name" | paste -sd, -)"
    base="$(volume_archive_name "$name")"
    state=missing
    if [ -f "$VOL_ROOT/secrets/$base" ] && [ -f "$sums" ] && seed_names "$sums" | grep -qxF "$base"; then
      state="archived $(date -r "$VOL_ROOT/secrets/$base" +%F)"
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "${size:-0}" "${users:--}" "$state"
  done < <(data_volumes)
}

_vol_print_rows() {
  local name bytes users state
  while IFS=$'\t' read -r name bytes users state; do
    printf '    %-48s %10s  users=%-14s %s\n' "$name" "$(human_bytes "$bytes")" "$users" "$state"
  done
}
