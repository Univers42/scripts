# shellcheck shell=bash
# volkey.sh — the proof that the operator alone holds a volumes target's key, and the restore drill
# that follows its push. Sourced; sets no shell options; needs config.sh, remote.sh, diffs.sh,
# state.sh and common.sh. Used when a target says `guard = sole-holder`.
#
#   v42_volkey_proof TARGET ROWS ME   status 1 and a message unless the env exists under exactly its
#                                     name, nobody else is `active`, ME's wrap unwraps the key, and a
#                                     previously drilled env still holds a tree
#   v42_volkey_drill TARGET           restore the vault into a scratch dir and compare every file
#                                     byte for byte; a pass writes the drilled marker
#
# The marker lives under the git common dir (`<common>/vault42/`) so a linked worktree or a
# submodule sees the same one, and it is never inside the checkout where the scan could take it.
#
# Caveat: keys ls `active` records what was synced, not who can read: an admin who re-keys and plants
# a wrap for the operator is invisible here. The proof therefore unwraps (`env files`), and still
# cannot see that case. Caveat: the drill proves the files come back from THIS key; it cannot prove a
# teammate's key opens them. No command here runs init, sync, grant or rotate.

v42_volkey_marker() {
  printf '%s/drilled.%s.%s.%s' "$(v42_state_dir "$(v42_cfg "$1" root)")" "$(v42_cfg "$1" org)" "$(v42_cfg "$1" project)" "$(v42_cfg "$1" env)"
}

# Sets V42_NOTREE=1 when the env holds no tree yet; status 1 when the wrap does not unwrap.
_v42_volkey_unwraps() {
  V42_NOTREE=0
  v42_envargs "$1"
  if _v42_call "$1" keystore env files "${V42_ENVARGS[@]}" --format '{{.Path}}'; then return 0; fi
  if [[ "$V42_ERR$V42_OUT" == *"holds no tree"* ]]; then
    V42_NOTREE=1
    return 0
  fi
  V42_VOLKEY_ERR="${V42_ERR//$'\n'/ | }"
  return 1
}

_v42_volkey_env_exists() {
  local listing env
  env="$(v42_cfg "$1" env)"
  if ! listing="$(_v42_in_root "$1" keystore env ls --project "$(v42_cfg "$1" project)" 2>&1)"; then
    note "env ls failed (${listing//$'\n'/ | }); this tool never creates or initialises an env: run 42ctl env ls --project $(v42_cfg "$1" project)"
    return 1
  fi
  awk -v name="$env" '$2 == name { found = 1 } END { exit !found }' <<<"$listing" || {
    note "no env named exactly '$env' in $(v42_cfg "$1" project): create it by hand with 42ctl env create, then 42ctl env init"
    return 1
  }
}

v42_volkey_proof() {
  local target="$1" others env
  env="$(v42_cfg "$target" env)"
  _v42_volkey_env_exists "$target" || return 1
  others="$(awk -v me="$3" '$2 == "active" && $1 != me { print $1 }' <<<"$2" | paste -sd' ')"
  if [ -n "$others" ]; then
    note "the $env key is also held by [$others]: raw databases would reach them; fix by hand: 42ctl env keys ls"
    return 1
  fi
  _v42_volkey_unwraps "$target" || {
    note "your wrap does not unwrap the $env key (${V42_VOLKEY_ERR}); this tool never runs init, sync or grant here"
    return 1
  }
  if [ "$V42_NOTREE" -eq 1 ] && [ -e "$(v42_volkey_marker "$target")" ]; then
    note "$env held a drilled tree and now holds none: it was re-keyed; do not push; run 42ctl env keys ls"
    return 1
  fi
}

v42_volkey_drill() {
  local target="$1" root table total
  root="$(v42_cfg "$target" root)"
  total="$(v42_remote_sizes "$target" | awk -F'\t' '{ n += $1 } END { print n + 0 }')"
  space_guard "$root" "$total" "$(v42_cfg "$target" min_free_mb)" || {
    note "pushed, but the restore drill could not run (no space to restore into)"
    return 1
  }
  table="$(v42_diff_exact "$target" volumes)" || {
    note "restore drill: pull --apply failed; the env may have been re-keyed by someone else: do not re-push"
    return 1
  }
  if [ -n "$table" ]; then
    note "restore drill: the vault does not give back what was pushed:"
    printf '%s\n' "$table" >&2
    return 1
  fi
  date -u +%FT%TZ >"$(v42_volkey_marker "$target")"
  note "restore drill: the vault gives back every pushed file"
}
