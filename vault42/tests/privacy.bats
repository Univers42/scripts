#!/usr/bin/env bats
# lib/privacy.sh alone: the plan (patterns, expected set, undecided gate) and the verify (both directions).
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  load_lib common state scan private config creds ctl kinds remote diffs stage privacy
  R="$(make_repo)"
  mkdir -p "$R/secrets"
  printf 1 >"$R/a.env"
  printf 1 >"$R/secrets/k.env"
  printf 1 >"$R/x.env.local"
  write_conf "$R" "private = secrets/*.env"
  v42_config_load "$CONF"
  export FT_PASSPHRASE=x
  V42_PUSH_PRIVATE=() V42_PUSH_SHARE=()
}

@test "plan: patterns are the config's, the flags', the stage archive and *.local, deduplicated" {
  write_conf "$R" "private = secrets/*.env *.local" "stage_unscanned_as = secrets/s.tgz"
  v42_config_load "$CONF"
  V42_PUSH_PRIVATE=('secrets/*.env')
  v42_privacy_plan t
  [ "${V42_PUSH_PATTERNS[*]}" = 'secrets/*.env *.local secrets/s.tgz' ]
}

@test "plan: the expected set is the local paths the patterns select" {
  v42_privacy_plan t
  [ "$V42_EXPECT_PRIVATE" = $'secrets/k.env\nx.env.local' ]
}

@test "plan: an undecided secrets/ file refuses and names it; --share decides it" {
  printf 1 >"$R/secrets/x.pem"
  run v42_privacy_plan t
  [ "$status" -eq 1 ]
  [[ "$output" == *secrets/x.pem* ]]
  V42_PUSH_SHARE=(secrets/x.pem)
  run v42_privacy_plan t
  [ "$status" -eq 0 ]
}

@test "verify: equal sets pass" {
  v42_privacy_plan t
  printf 'secrets/k.env\nx.env.local\n' >"$FAKE42/private.e"
  printf '1 a.env\n' >"$FAKE42/files.e"
  run v42_privacy_verify t
  [ "$status" -eq 0 ]
}

@test "verify: a path planned private but stored shared is a possible disclosure" {
  v42_privacy_plan t
  printf 'secrets/k.env\n' >"$FAKE42/private.e"
  printf '1 a.env\n' >"$FAKE42/files.e"
  run v42_privacy_verify t
  [ "$status" -eq 1 ]
  [[ "$output" == *"x.env.local"*"SHARED"* ]]
}

@test "verify: a path stored private but planned shared is a possible disclosure" {
  v42_privacy_plan t
  printf 'secrets/k.env\nx.env.local\na.env\n' >"$FAKE42/private.e"
  printf '1 a.env\n' >"$FAKE42/files.e"
  run v42_privacy_verify t
  [ "$status" -eq 1 ]
  [[ "$output" == *"a.env"*"planned shared"* ]]
}

@test "plan: a stage archive the scan would not upload is refused, never silently left out of the push" {
  printf 1 >"$R/unscanned.tgz"
  write_conf "$R" "private = secrets/*.env" "stage_unscanned_as = unscanned.tgz"
  v42_config_load "$CONF"
  run v42_privacy_plan t
  [ "$status" -eq 1 ]
  [[ "$output" == *unscanned.tgz* ]]
  [[ "$output" == *"scan"* ]]
}

@test "plan: a stage archive the scan takes is in the expected private set" {
  printf 1 >"$R/secrets/s.tgz"
  write_conf "$R" "private = secrets/*.env" "stage_unscanned_as = secrets/s.tgz"
  v42_config_load "$CONF"
  v42_privacy_plan t
  [[ "$V42_EXPECT_PRIVATE" == *secrets/s.tgz* ]]
}
