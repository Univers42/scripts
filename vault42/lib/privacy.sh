# shellcheck shell=bash
# privacy.sh — decide, before a push, which files are sealed to the pusher alone, and check the vault
# against that plan afterwards. Sourced; sets no shell options; needs config.sh, private.sh, stage.sh,
# diffs.sh, remote.sh and common.sh.
#
#   v42_privacy_plan TARGET   from V42_PUSH_PRIVATE (--private flags) and V42_PUSH_SHARE (--share flags),
#                             sets V42_PUSH_PATTERNS (the --private arguments, deduplicated: the target's
#                             `private` and `private_add`, the flags, the stage archives, `*.local`) and
#                             V42_EXPECT_PRIVATE (the local paths those patterns select). Status 1
#                             naming every secrets/ file (at any depth) nobody classified, and
#                             a staged archive the scan or the patterns would not carry.
#   v42_privacy_differs TARGET status 0 when the vault's private set is not the plan (1 same, 2 unreadable)
#   v42_privacy_verify TARGET status 1 naming every difference between V42_EXPECT_PRIVATE and the
#                             vault's private set, in both directions
#
# `*.local` and the stage archives are passed explicitly even though 42ctl forces `*.local` itself, so
# the plan never depends on a default this tool cannot see change.
#
# Caveat: files another member pushed private are invisible to this member, so the verify compares the
# paths THIS checkout holds; whether a push keeps the others is assumption A2 (README), unverified.
# Caveat: `*.local` is 42ctl 0.1.16's forced-private list; a 42ctl that forces more makes the verify
# refuse on the extra paths, never pass silently.

declare -ga V42_PUSH_PRIVATE=() V42_PUSH_SHARE=() V42_PUSH_PATTERNS=()
V42_EXPECT_PRIVATE=""
V42_PRIV_MISSING=""
V42_PRIV_EXTRA=""

# A staged archive the scan does not take is never uploaded; one the patterns do not select is
# uploaded shared. Either way the push would report success with the files unprotected or missing.
_v42_privacy_archives_travel() {
  local target="$1" paths="$2" root archive
  root="$(v42_cfg "$target" root)"
  while IFS= read -r archive; do
    [ -e "$root/$archive" ] || continue
    grep -qxF -- "$archive" <<<"$paths" || {
      note "refusing: the staged archive $archive is not a file 42ctl's scan takes, so it would never be uploaded; name it under secrets/ or *.secrets"
      return 1
    }
    grep -qxF -- "$archive" <<<"$V42_EXPECT_PRIVATE" || {
      note "refusing: the staged archive $archive is not in the planned private set, so it would go out shared"
      return 1
    }
  done < <(v42_stage_paths "$target")
}

v42_privacy_plan() {
  local target="$1" paths shared undecided
  paths="$(v42_local_sizes "$(v42_cfg "$target" root)" | cut -f2)"
  mapfile -t V42_PUSH_PATTERNS < <(
    {
      v42_cfg_private "$target"
      printf '%s\n' "${V42_PUSH_PRIVATE[@]}"
      v42_stage_paths "$target"
      printf '%s\n' '*.local'
    } | awk 'NF && !seen[$0]++'
  )
  shared="$(
    read -ra words <<<"$(v42_cfg "$target" shared)"
    printf '%s\n' "${words[@]}" "${V42_PUSH_SHARE[@]}"
  )"
  undecided="$(vault42_undecided "$(printf '%s\n' "${V42_PUSH_PATTERNS[@]}")" "$shared" <<<"$paths" | paste -sd' ')"
  if [ -n "$undecided" ]; then
    note "refusing: these secrets/ files are neither private nor shared, and a push would seal them with no decision: $undecided — pass --private PATTERN or --share PATH, or list them under private/shared in the config"
    return 1
  fi
  V42_EXPECT_PRIVATE="$(vault42_filter_private "$(printf '%s\n' "${V42_PUSH_PATTERNS[@]}")" <<<"$paths" | LC_ALL=C sort -u)"
  _v42_privacy_archives_travel "$target" "$paths"
}

# Sets V42_PRIV_MISSING (expected private, stored shared) and V42_PRIV_EXTRA (stored private, planned
# shared); status 1 when the vault cannot be read.
_v42_privacy_delta() {
  local actual
  actual="$(v42_remote_private "$1")" || return 1
  V42_PRIV_MISSING="$(LC_ALL=C comm -23 <(grep . <<<"$V42_EXPECT_PRIVATE" || true) <(grep . <<<"$actual" || true) | paste -sd' ')"
  V42_PRIV_EXTRA="$(LC_ALL=C comm -13 <(grep . <<<"$V42_EXPECT_PRIVATE" || true) <(grep . <<<"$actual" || true) | paste -sd' ')"
}

# Status 0 when the vault's private set differs from the plan, 1 when it matches, 2 when unreadable.
# Quiet: it decides whether an otherwise empty push still has something to change (a re-seal).
v42_privacy_differs() {
  _v42_privacy_delta "$1" || return 2
  [ -n "$V42_PRIV_MISSING$V42_PRIV_EXTRA" ]
}

v42_privacy_verify() {
  _v42_privacy_delta "$1" || return 1
  [ -z "$V42_PRIV_MISSING" ] || note "possible disclosure: $V42_PRIV_MISSING — expected private (sealed to you alone) but the vault holds them SHARED; treat the key holders as readers"
  [ -z "$V42_PRIV_EXTRA" ] || note "possible disclosure: $V42_PRIV_EXTRA — listed private by the vault but planned shared; the plan and the vault disagree about who reads them"
  [ -z "$V42_PRIV_MISSING$V42_PRIV_EXTRA" ]
}
