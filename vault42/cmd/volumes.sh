# shellcheck shell=bash
# volumes.sh — `vault42 volumes list|capture|restore`: docker data volumes as archives under the
# volumes target's secrets/, so the ordinary push carries them. Defines functions only; sourced by
# vault42.sh. These subcommands need docker and no credential, so the credentials are dropped first.
#
# A capture is a cold copy: the containers using a volume are stopped, archived, restarted on every
# exit path. Their ids go to <git common dir>/vault42/stopped.TARGET before `docker stop`, so a
# SIGKILL leaves the next capture able to restart them.
#
# Never move a volumes root after its first push: 42ctl derives the project id from its path.
# Caveat: sizes come from `docker system df -v`, which prints three significant digits in decimal
# units, so the space check is off by up to ~0.5% and ignores compression (it over-asks).
# Caveat: a container started by something else between the stop and the restart is not tracked.
# Caveat: the stack guard reads GROBASE_ENV from the environment and from stack_file; a stack whose
# environment is named some other way is not recognised.

VOL_STATE=""
VOL_ROOT=""

_vol_target() {
  local t
  local -a found=()
  v42_pick_targets || return 2
  if [ -n "$V42_TARGET_FLAG" ]; then
    V42_T="${V42_SEL[0]}"
  else
    for t in "${V42_SEL[@]}"; do
      case " $(v42_cfg "$t" kinds) " in *" volumes "*) found+=("$t") ;; esac
    done
    [ "${#found[@]}" -eq 1 ] || {
      usage_error "volumes acts on one target with kinds = volumes; pick one with --target (found ${#found[@]})"
      return 2
    }
    V42_T="${found[0]}"
  fi
  VOL_ROOT="$(v42_cfg "$V42_T" root)"
  VOL_STATE="$(v42_state_dir "$VOL_ROOT")/stopped.$V42_T" || return 1
  V42_MIN_FREE_MB="$(v42_cfg "$V42_T" min_free_mb)"
}

# C11: a staging or prod stack's data is not copied by this command, whatever mode the operator is in.
_vol_stack_guard() {
  local target="$1" file seen stack word
  file="$(v42_cfg "$target" stack_file)"
  seen="${GROBASE_ENV:-} $([ -z "$file" ] || get_env "$file" GROBASE_ENV || true)"
  for stack in $seen; do
    for word in $(v42_cfg "$target" refuse_on_env); do
      [ "$word" != "$stack" ] || {
        note "refusing: GROBASE_ENV=$stack is in refuse_on_env; capture is for a dev stack; change it there, or capture on that host by hand"
        return 1
      }
    done
  done
}

_vol_list() {
  local rows
  rows="$(_vol_rows)" || return 1
  [ -z "$rows" ] || _vol_print_rows <<<"$rows"
  printf '%s data volumes, %s not archived yet\n' "$(count_lines "$rows")" "$(grep -c 'missing$' <<<"$rows" || true)"
}

# VOL_ROWS = the rows to capture, narrowed by --only.
_vol_select() {
  local all name
  all="$(_vol_rows)" || return 1
  VOL_ROWS="$all"
  [ "$#" -gt 0 ] || return 0
  for name; do
    cut -f1 <<<"$all" | grep -qxF "$name" || {
      note "$name is not a data volume; list them: vault42 volumes list"
      return 1
    }
  done
  VOL_ROWS="$(for name; do awk -F'\t' -v n="$name" '$1 == n' <<<"$all"; done)"
}

_vol_space() {
  local total
  total="$(awk -F'\t' '{ s += $2 } END { printf "%.0f", s }' <<<"$VOL_ROWS")"
  note "$(count_lines "$VOL_ROWS") volumes, $(human_bytes "$total") raw (docker system df -v)"
  space_guard "$VOL_ROOT/secrets" "$total" "$V42_MIN_FREE_MB"
}

# Restarts the recorded ids; the record goes only when every one runs. Idempotent, so it is safe as
# both the normal path and the exit-trap cleanup.
_vol_restart() {
  local id bad=0
  [ -s "$VOL_STATE" ] || {
    rm -f "$VOL_STATE"
    return 0
  }
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    docker start "$id" >/dev/null 2>&1 || true
    if [ "$(docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null)" != true ]; then
      note "container $id is not running; start it: docker start $id"
      bad=1
    fi
  done <"$VOL_STATE"
  [ "$bad" -eq 0 ] || return 1
  rm -f "$VOL_STATE"
}

_vol_cleanup() {
  rm -f "$VOL_ROOT"/secrets/.volume-*.stale
  _vol_restart
}

_vol_stop_users() {
  local name
  local -a ids=()
  mapfile -t ids < <(for name; do volume_users "$name"; done | sort -u)
  [ "${#ids[@]}" -gt 0 ] || return 0
  printf '%s\n' "${ids[@]}" >"$VOL_STATE"
  note "stopping ${#ids[@]} containers for a cold copy: ${ids[*]}"
  docker stop "${ids[@]}" >/dev/null
}

# VOL_WRITTEN = archive basenames; status 2 after a floor refusal (the rest are not tried).
_vol_archive_all() {
  local name rc=0 one
  VOL_WRITTEN=()
  for name; do
    one=0
    volume_archive "$name" "$VOL_ROOT/secrets" || one=$?
    case "$one" in
      0) VOL_WRITTEN+=("$(volume_archive_name "$name")") ;;
      2)
        note "out of space at $VOL_ROOT: kept the ${#VOL_WRITTEN[@]} archives already written; free space, then rerun"
        return 2
        ;;
      *) rc=1 ;;
    esac
  done
  return "$rc"
}

_vol_capture_run() {
  local rc=0
  local -a names=()
  if [ -s "$VOL_STATE" ]; then
    note "a previous capture was killed: restarting its containers first"
    _vol_restart || return 1
  fi
  _vol_select "$@" || return 1
  _vol_space || return 1
  mapfile -t names < <(cut -f1 <<<"$VOL_ROWS")
  mkdir -p "$VOL_ROOT/secrets"
  chmod 700 "$VOL_ROOT/secrets"
  v42_on_exit _vol_cleanup
  _vol_stop_users "${names[@]}" || rc=1
  if [ "$rc" -eq 0 ]; then _vol_archive_all "${names[@]}" || rc=1; fi
  _vol_restart || rc=1
  if [ "${#VOL_WRITTEN[@]}" -gt 0 ]; then seed_sums_put "$VOL_ROOT/secrets" "${VOL_WRITTEN[@]}" || rc=1; fi
  note "captured ${#VOL_WRITTEN[@]} of ${#names[@]} volumes into $VOL_ROOT/secrets"
  return "$rc"
}

_vol_capture_plan() {
  local ids
  _vol_select "$@" || return 1
  _vol_space || return 1
  _vol_print_rows <<<"$VOL_ROWS"
  ids="$(cut -f3 <<<"$VOL_ROWS" | tr ',' '\n' | grep -v '^-$' | sort -u | paste -sd' ' -)"
  note "plan: would stop [${ids:-none}], archive into $VOL_ROOT/secrets, restart them; nothing written"
}

_vol_capture() {
  local plan=0 arg
  local -a only=()
  while [ "$#" -gt 0 ]; do
    arg="$1"
    shift
    case "$arg" in
      --plan) plan=1 ;;
      --only)
        [ "$#" -gt 0 ] || {
          usage_error "usage: vault42 volumes capture [--plan] [--only NAME]…"
          return 2
        }
        only+=("$1")
        shift
        ;;
      *)
        usage_error "usage: vault42 volumes capture [--plan] [--only NAME]…   e.g. vault42 volumes capture --plan"
        return 2
        ;;
    esac
  done
  _vol_stack_guard "$V42_T" || return 1
  if [ "$plan" -eq 1 ]; then
    _vol_capture_plan "${only[@]}"
    return
  fi
  v42_locked "$VOL_ROOT" _vol_capture_run "${only[@]}"
}

# One restore: ARG is an archive path, or a volume name whose archive sits in the target's secrets/.
_vol_restore_one() {
  local arg="$1" name="${2:-}" archive="$1"
  if [ ! -f "$archive" ] && [ -f "$VOL_ROOT/secrets/$(volume_archive_name "$arg")" ]; then
    archive="$VOL_ROOT/secrets/$(volume_archive_name "$arg")"
    name="$arg"
  fi
  if [ -z "$name" ]; then
    name="$(basename "$archive")"
    name="${name#volume-}"
    name="${name%.tar.gz}"
  fi
  if [ -n "$(volume_users "$name" 2>/dev/null)" ]; then
    note "volume $name is in use by a running container; stop it first"
    return 1
  fi
  volume_restore "$archive" "$name" && note "restored $archive into volume $name"
}

_vol_restore() {
  local all=0 arg rc=0 f
  local -a pos=()
  export V42_FORCE=0
  for arg; do
    case "$arg" in
      --all) all=1 ;;
      --force) export V42_FORCE=1 ;;
      *) pos+=("$arg") ;;
    esac
  done
  if [ "$all" -eq 1 ]; then
    for f in "$VOL_ROOT"/secrets/volume-*.tar.gz; do
      [ -e "$f" ] || {
        note "no volume archive under $VOL_ROOT/secrets"
        return 1
      }
      _vol_restore_one "$f" || rc=1
    done
    return "$rc"
  fi
  [ "${#pos[@]}" -ge 1 ] && [ "${#pos[@]}" -le 2 ] || {
    usage_error "usage: vault42 volumes restore [--force] ARCHIVE|NAME [NAME] | --all   e.g. vault42 volumes restore --all"
    return 2
  }
  _vol_restore_one "${pos[@]}"
}

cmd_volumes() {
  local sub="${1:-}" name
  shift || true
  case "$sub" in list | capture | restore) ;; *)
    usage_error "usage: vault42 volumes list | capture [--plan] [--only NAME]… | restore [--force] ARCHIVE|NAME | restore --all"
    return 2
    ;;
  esac
  for name in $V42_CRED_ALL; do unset "$name"; done
  _vol_target || return $?
  case "$sub" in
    list) _vol_list ;;
    capture) _vol_capture "$@" ;;
    restore) _vol_restore "$@" ;;
  esac
}
