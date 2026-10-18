# shellcheck shell=bash
# volumes.sh — docker data volumes as files, so vault42 can carry them like any other seed.
# Sourced; sets no shell options. Needs `docker` on PATH.
#
#   volume_is_cache NAME        status 0 for a dependency/build cache (gobuild, gomod, cargo-home,
#                               pnpm_store, node_modules): rebuilt from the network, not data.
#   volume_is_empty NAME        status 0 when the volume holds no entry.
#   data_volumes                every non-cache, non-empty volume, sorted, one per line; the
#                               emptiness of all of them is checked in one container (per-volume
#                               fallback if that fails).
#   volume_users NAME           ids of the RUNNING containers that mount NAME.
#   volume_archive_name NAME    the archive basename: volume-NAME.tar.gz, with every ".bak" in NAME
#                               written "_bak" and a trailing ".stale" "_stale" (42ctl never uploads
#                               such names).
#   volume_archive NAME DIR     DIR/<volume_archive_name>, written atomically. 2 = refused for lack
#                               of free space, 1 = failed (nothing left behind).
#   volume_restore ARCHIVE NAME unpack into NAME, creating it; refuses a non-empty volume unless
#                               V42_FORCE=1.
#
# Containers run with --network none from TAR_IMAGE (default mongo:7): it is already on the host
# and ships GNU tar, and with no network nothing can be installed into it.
#
# Caveat: a renamed archive (volume_archive_name) does not map back to its volume name; restore
# it with an explicit NAME. Caveat: a volume copied while its engine runs is not consistent;
# callers stop the volume_users first. Caveat: the free-space floor (V42_MIN_FREE_MB, default
# 1024) is checked before each archive and is not an estimate of the archive's size.

TAR_IMAGE="${TAR_IMAGE:-mongo:7}"

# Caveat: classification is by name suffix only: a data volume named like a cache is skipped
# (not backed up), a cache under any other name is archived (wasted space).
volume_is_cache() {
  case "$1" in
  *gobuild | *gomod | *cargo-home | *pnpm_store | *node_modules) return 0 ;;
  esac
  return 1
}

volume_is_empty() {
  docker run --rm --network none -v "$1:/v:ro" --entrypoint sh "$TAR_IMAGE" -c '[ -z "$(ls -A /v)" ]'
}

# Prints the index of every non-empty volume among NAME...: one container mounts them all
# read-only at /v/<index>, so 100 volumes cost one start instead of 100.
_data_volumes_batch() {
  local -a mounts=() dirs=()
  local i
  for i in "${!VOLUME_NAMES[@]}"; do
    mounts+=(-v "${VOLUME_NAMES[$i]}:/v/$i:ro")
    dirs+=("/v/$i")
  done
  docker run --rm --network none "${mounts[@]}" --entrypoint sh "$TAR_IMAGE" \
    -c 'i=0; for d; do [ -z "$(ls -A "$d")" ] || printf "%s\n" "$i"; i=$((i + 1)); done' sh "${dirs[@]}"
}

data_volumes() {
  local name indexes i
  local -a VOLUME_NAMES=()
  while read -r name; do
    [ -n "$name" ] || continue
    ! volume_is_cache "$name" || continue
    VOLUME_NAMES+=("$name")
  done < <(docker volume ls -q | LC_ALL=C sort)
  [ "${#VOLUME_NAMES[@]}" -gt 0 ] || return 0
  if indexes="$(_data_volumes_batch)"; then
    for i in $indexes; do printf '%s\n' "${VOLUME_NAMES[$i]}"; done
    return 0
  fi
  printf 'data_volumes: batched emptiness check failed; checking volumes one by one\n' >&2
  for name in "${VOLUME_NAMES[@]}"; do
    ! volume_is_empty "$name" || continue
    printf '%s\n' "$name"
  done
}

volume_users() { docker ps -q --filter "volume=$1"; }

volume_archive_name() {
  local name="${1//.bak/_bak}"
  case "$name" in
  *.stale) name="${name%.stale}_stale" ;;
  esac
  printf 'volume-%s.tar.gz' "$name"
}

# 42ctl uploads every regular file under secrets/ but skips names ending .stale, so the tmp is
# named that way: a crash or concurrent push cannot publish a half-written archive. It sits in
# DIR itself so the final mv stays on one filesystem (atomic), and is removed on every failure.
volume_archive() {
  local name="$1" dir="$2" tmp final free base
  base="$(volume_archive_name "$name")"
  tmp="$dir/.$base.stale"
  final="$dir/$base"
  free="$(df -Pm "$dir" | awk 'NR == 2 { print $4 }')"
  if [ "${free:-0}" -lt "${V42_MIN_FREE_MB:-1024}" ]; then
    printf 'volume_archive: %s MB free in %s, below the %s MB floor; %s not archived\n' \
      "${free:-0}" "$dir" "${V42_MIN_FREE_MB:-1024}" "$name" >&2
    return 2
  fi
  if docker run --rm --network none -v "$name:/v:ro" -v "$dir:/out" --entrypoint tar "$TAR_IMAGE" \
    --numeric-owner -C /v -czf "/out/.$base.stale" . &&
    gzip -t "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$final"; then
    return 0
  fi
  rm -f "$tmp"
  printf 'volume_archive: archiving %s into %s failed\n' "$name" "$dir" >&2
  return 1
}

volume_restore() {
  local archive="$1" name="$2"
  if [ ! -f "$archive" ] || ! gzip -t "$archive" 2>/dev/null; then
    printf 'volume_restore: %s is missing or not a valid gzip\n' "$archive" >&2
    return 1
  fi
  docker volume inspect "$name" >/dev/null 2>&1 || docker volume create "$name" >/dev/null || return 1
  if [ "${V42_FORCE:-0}" != 1 ] && ! volume_is_empty "$name"; then
    printf 'volume_restore: volume %s is not empty; rerun with V42_FORCE=1 to unpack over it\n' "$name" >&2
    return 1
  fi
  docker run --rm --network none -v "$name:/v" -v "$(dirname "$archive"):/s:ro" --entrypoint tar "$TAR_IMAGE" \
    --numeric-owner -C /v -xzf "/s/$(basename "$archive")"
}
