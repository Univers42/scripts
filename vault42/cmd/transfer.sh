# shellcheck shell=bash
# transfer.sh — `vault42 pull` and `vault42 push [FILE…]`. Defines functions only; sourced by
# vault42.sh. The guards are in lib/push.sh and lib/privacy.sh; this file orders them.
#
# Push order: kinds -> hooks checked -> credential -> lock -> stage -> stale files -> version gate ->
# pre_push -> route -> diff -> drop guard -> privacy plan -> object-store gate -> summary -> confirm ->
# re-diff -> push -> verify. Every refusal before the push leaves the vault untouched.
#
# Caveat: the re-diff after the confirm compares the same listing as the first diff, so a same-size
# edit made by another member inside that window is not seen (file mode compares bytes and is). The
# window is the time a person takes to answer the prompt.

# _push_file_rows TABLE: status 1 naming every row whose path is not one of V42_PUSH_FILES.
_push_file_rows() {
  local line path bad="" hint=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="$(v42_diff_row_path "$line")" || continue
    printf '%s\n' "${V42_PUSH_FILES[@]}" | grep -qxF -- "$path" && continue
    bad="$bad $path"
    hint="$hint
  vault42 pull --apply --only $(printf '%q' "$path")"
  done <<<"$1"
  [ -z "$bad" ] || {
    note "refusing: pushing ${V42_PUSH_FILES[*]} would also replace the vault's tree, but these differ too:$bad. Restore them first, or push everything with: vault42 push$hint"
    return 1
  }
}

_push_check_files() {
  local root="$1" file
  for file in "${V42_PUSH_FILES[@]}"; do
    vault42_scan "$root" | grep -qxF -- "$file" || {
      note "$file is not a file 42ctl's scan takes under $root"
      return 2
    }
  done
}

_push_table() {
  if [ "${#V42_PUSH_FILES[@]}" -gt 0 ]; then
    v42_diff_exact "$1" "${V42_KINDS[@]}"
  else
    v42_diff_table "$1" "${V42_KINDS[@]}"
  fi
}

# FILE, --drop, --share and --private only mean something to a team push. The personal and fallback
# routes run `42ctl push`, which sends the whole tree: honouring none of them silently is how a push
# of one file once sent everything.
_push_team_only() {
  local route="$1" used=""
  [ "$route" != team ] || return 0
  [ "${#V42_PUSH_FILES[@]}" -eq 0 ] || used="$used FILE"
  [ "${#V42_PUSH_DROPS[@]}" -eq 0 ] || used="$used --drop"
  [ "${#V42_PUSH_SHARE[@]}" -eq 0 ] || used="$used --share"
  [ "${#V42_PUSH_PRIVATE[@]}" -eq 0 ] || used="$used --private"
  [ -z "$used" ] || {
    note "refusing:$used apply only to a team push; the $route push sends the whole tree and honours none of them"
    return 2
  }
}

_push_exec() {
  local target="$1" pattern
  local -a args=()
  for pattern in "${V42_PUSH_PATTERNS[@]}"; do args+=(--private "$pattern"); done
  v42_envargs "$target"
  if [ "$V42_ROUTE" = team ]; then
    (cd "$(v42_cfg "$target" root)" && v42_ctl keystore env push "${V42_ENVARGS[@]}" "${args[@]}")
  else
    (cd "$(v42_cfg "$target" root)" && v42_ctl keystore push --project "$(v42_cfg "$target" project)")
  fi
}

_push_authorise() {
  [ "${V42_PUSH_YES:-0}" -eq 0 ] || return 0
  v42_confirm "push?" || {
    note "not confirmed (no terminal, or the answer was not y): rerun with --yes"
    return 1
  }
}

_push_verify() {
  local table
  table="$(_push_table "$1")" || return 1
  if [ -n "$table" ]; then
    note "the vault does not match this checkout after the push:"
    printf '%s\n' "$table" >&2
    return 1
  fi
  v42_privacy_verify "$1" || return 1
  note "the vault matches this checkout and its private set is the planned one"
}

# Everything up to and including the confirm; leaves the table in V42_PUSH_TABLE.
_push_prepare() {
  local target="$1" root
  root="$(v42_cfg "$target" root)"
  v42_stage "$target" && v42_stage_stale "$root" && v42_ctl_gate push || return 1
  v42_hook_run "$root" "$(v42_cfg "$target" pre_push)" none || {
    note "the pre_push hook failed: nothing was pushed"
    return 1
  }
  v42_push_route "$target" || return 1
  _push_team_only "$V42_ROUTE" || return 2
  V42_PUSH_TABLE=""
  if [ "$V42_ROUTE" = team ]; then
    [ "${#V42_PUSH_FILES[@]}" -eq 0 ] || _push_check_files "$root" || return $?
    V42_PUSH_TABLE="$(_push_table "$target")" || return 1
    [ "${#V42_PUSH_FILES[@]}" -eq 0 ] || _push_file_rows "$V42_PUSH_TABLE" || return 1
    v42_push_drops "$V42_PUSH_TABLE" && v42_privacy_plan "$target" || return 1
  fi
  v42_push_s3_gate "$target" || return 1
  v42_push_summary "$target" "$V42_PUSH_TABLE"
  _push_authorise
}

# Status 0 when a push still has something to change; 10 when it has not (the caller stops with 0).
# An empty table says the files match, not that their sealing does: `private_add = a.env` after a
# shared push must still re-seal a.env.
_push_nothing_to_change() {
  local rc=0
  [ -z "$V42_PUSH_TABLE" ] || return 0
  v42_privacy_differs "$1" || rc=$?
  case "$rc" in
  0) note "the files match but the vault's private set is not the plan: pushing to re-seal" ;;
  1)
    note "the vault already matches this checkout: nothing to push"
    return 10
    ;;
  *) return 1 ;;
  esac
}

_push_run() {
  local target="$1" again rc
  _push_prepare "$target" || return $?
  if [ "$V42_ROUTE" = team ]; then
    again="$(_push_table "$target")" || return 1
    [ "$again" = "$V42_PUSH_TABLE" ] || {
      note "the vault changed while you were deciding: nothing was pushed; review again"
      return 1
    }
    _push_nothing_to_change "$target" || {
      rc=$?
      [ "$rc" -ne 10 ] || return 0
      return "$rc"
    }
  fi
  _push_exec "$target" || {
    note "the push failed: see the 42ctl error above"
    return 1
  }
  if [ "$V42_ROUTE" = team ]; then _push_verify "$target" || return 1; fi
  if [ "$(v42_cfg "$target" guard)" = sole-holder ]; then v42_volkey_drill "$target" || return 1; fi
  [ "$V42_ROUTE" != fallback ] || return 3
}

cmd_push() {
  V42_PUSH_YES=0 V42_PUSH_FILES=() V42_PUSH_DROPS=() V42_PUSH_PRIVATE=() V42_PUSH_SHARE=()
  v42_push_allow_personal 0
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --yes) V42_PUSH_YES=1 ;;
    --personal) v42_push_allow_personal ;;
    --drop | --share | --private)
      [ "$#" -gt 1 ] || {
        usage_error "$1 needs a value"
        return 2
      }
      case "$1" in
      --drop) V42_PUSH_DROPS+=("$2") ;;
      --share) V42_PUSH_SHARE+=("$2") ;;
      --private) V42_PUSH_PRIVATE+=("$2") ;;
      esac
      shift
      ;;
    -*)
      usage_error "unknown push option '$1'; run: vault42 help push"
      return 2
      ;;
    *) V42_PUSH_FILES+=("$1") ;;
    esac
    shift
  done
  v42_single_target || return 2
  _push_team_only "$(v42_cfg "$V42_T" mode)" || return 2
  v42_kind_require_full "$V42_T" "${V42_KINDS[@]}" || return 2
  v42_hook_check "$(v42_cfg "$V42_T" root)" "$(v42_cfg "$V42_T" pre_push)" || return 2
  v42_cred_require passphrase || return 5
  v42_locked "$(v42_cfg "$V42_T" root)" _push_run "$V42_T"
}

# ---- pull ----

_pull_total_bytes() {
  v42_remote_sizes "$1" | awk -F'\t' '{ n += $1 } END { print n + 0 }'
}

_pull_one() {
  local target="$1" apply="$2" root pattern total
  local -a args=()
  root="$(v42_cfg "$target" root)"
  v42_hook_check "$root" "$(v42_cfg "$target" post_pull)" || return 2
  v42_ctl_gate read || true
  if [ "${#V42_PULL_ONLY[@]}" -gt 0 ]; then
    for pattern in "${V42_PULL_ONLY[@]}"; do args+=(--only "$pattern"); done
  else
    while IFS= read -r pattern; do [ -z "$pattern" ] || args+=(--only "$pattern"); done < <(v42_kind_only "$target" "${V42_KINDS[@]}")
  fi
  if [ "$apply" -eq 1 ]; then
    total="$(_pull_total_bytes "$target")" || return 1
    space_guard "$root" "$total" "$(v42_cfg "$target" min_free_mb)" || return 1
    args+=(--apply)
  fi
  v42_envargs "$target"
  (cd "$root" && v42_ctl keystore env pull "${V42_ENVARGS[@]}" "${args[@]}") || return 1
  [ "$apply" -eq 1 ] || {
    note "preview only: add --apply to write these files"
    return 0
  }
  # The hook may run vault42 itself (secret get), so it must not meet this run's lock.
  vault42_unlock_lock
  v42_hook_run "$root" "$(v42_cfg "$target" post_pull)" hook || {
    note "the post_pull hook failed; the files were restored"
    return 1
  }
}

cmd_pull() {
  local apply=0 t rc=0
  V42_PULL_ONLY=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --apply) apply=1 ;;
    --only)
      [ "$#" -gt 1 ] || {
        usage_error "--only needs a path or pattern"
        return 2
      }
      V42_PULL_ONLY+=("$2")
      shift
      ;;
    *)
      usage_error "unknown pull argument '$1'; run: vault42 help pull"
      return 2
      ;;
    esac
    shift
  done
  v42_cred_require passphrase || return 5
  v42_scoped_targets || return 2
  for t in "${V42_SEL[@]}"; do
    v42_locked "$(v42_cfg "$t" root)" _pull_one "$t" "$apply" || rc=$?
  done
  return "$rc"
}
