# shellcheck shell=bash
# privacy.sh — decide, before a push, which files are sealed to the pusher alone, and check the vault
# against that plan afterwards. Sourced; sets no shell options; needs config.sh, private.sh, stage.sh,
# diffs.sh, remote.sh and common.sh.
#
#   v42_privacy_plan TARGET   from V42_PUSH_PRIVATE (--private flags) and V42_PUSH_SHARE (--share flags),
#                             sets V42_PUSH_PATTERNS (the --private arguments, deduplicated: the target's
#                             `private` and `private_add`, the flags, the stage archives, `*.local`) and
#                             V42_EXPECT_PRIVATE (the local paths those patterns select). Status 1
#                             naming every secrets/ file nobody classified.
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
}

v42_privacy_verify() {
  local actual missing extra
  actual="$(v42_remote_private "$1")" || return 1
  missing="$(LC_ALL=C comm -23 <(grep . <<<"$V42_EXPECT_PRIVATE" || true) <(grep . <<<"$actual" || true) | paste -sd' ')"
  extra="$(LC_ALL=C comm -13 <(grep . <<<"$V42_EXPECT_PRIVATE" || true) <(grep . <<<"$actual" || true) | paste -sd' ')"
  [ -z "$missing" ] || note "possible disclosure: $missing — expected private (sealed to you alone) but the vault holds them SHARED; treat the key holders as readers"
  [ -z "$extra" ] || note "possible disclosure: $extra — listed private by the vault but planned shared; the plan and the vault disagree about who reads them"
  [ -z "$missing$extra" ]
}
