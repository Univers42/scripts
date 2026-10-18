#!/usr/bin/env bats
# lib/remote.sh alone against the fake 42ctl: row parsing, the C14 refusal of blank fields, and the
# key-state helpers.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  load_lib common config creds ctl remote
  R="$(make_repo)"
  write_conf "$R"
  v42_config_load "$CONF"
  export FT_PASSPHRASE=x
  printf '5 a.env\n12 secrets/my key.pem\n' >"$FAKE42/files.e"
  printf 'secrets/my key.pem\n' >"$FAKE42/private.e"
}

teardown() { assert_no_stdin_violation; }

@test "sizes: SIZE<TAB>PATH, a path with a space survives" {
  run v42_remote_sizes t
  [ "$status" -eq 0 ]
  [ "$output" = $'5\ta.env\n12\tsecrets/my key.pem' ]
}

@test "sizes: the call carries org, project and env, in the target's root" {
  run v42_remote_sizes t
  run grep -c "cwd=$R argv=env files --org o --project p --env e --format {{.Size}} {{.Path}} pass=yes" "$FAKE42/argv.log"
  [ "$output" = 1 ]
}

@test "listing: SIZE PRIVATE PATH" {
  run v42_remote_listing t
  [ "$output" = $'5 false a.env\n12 true secrets/my key.pem' ]
}

@test "private: sorted private paths; none private is an empty set, not a failure" {
  run v42_remote_private t
  [ "$output" = 'secrets/my key.pem' ]
  : >"$FAKE42/private.e"
  run v42_remote_private t
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an environment that holds no tree is an empty listing" {
  rm "$FAKE42/files.e"
  run v42_remote_sizes t
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a failing listing is status 1 naming the command to run" {
  touch "$FAKE42/files-fail"
  run --separate-stderr v42_remote_sizes t
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"listing failed"* && "$stderr" == *"42ctl env files --org o --project p --env e"* ]]
}

@test "C14: a blank field in env files is refused, naming the command" {
  touch "$FAKE42/files-blank"
  run --separate-stderr v42_remote_sizes t
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"env files"* && "$stderr" == *"blank"* ]]
  run --separate-stderr v42_remote_listing t
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"blank"* ]]
}

@test "keys: MEMBER STATE rows, and the helpers read them" {
  printf 'acc-1 active\n7704efb0-5a6a-4117-9cdd-a9265a8fc350 pending\nacc-3 active\n' >"$FAKE42/keys.e"
  rows="$(v42_keys_rows t)"
  [ "$(v42_my_state "$rows" acc-1)" = active ]
  [ "$(v42_my_state "$rows" 7704efb0-5a6a-4117-9cdd-a9265a8fc350)" = pending ]
  [ "$(v42_my_state "$rows" nobody)" = absent ]
  [ "$(v42_holders "$rows")" = $'acc-1\nacc-3' ]
}

@test "C14: a blank field in env keys ls is refused, naming the command" {
  printf 'acc-1 \n' >"$FAKE42/keys.e"
  run --separate-stderr v42_keys_rows t
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"env keys ls"* && "$stderr" == *blank* ]]
}

@test "keys: a failing call is status 1" {
  printf 'acc-1 active\n' >"$FAKE42/keys.e"
  touch "$FAKE42/keys-fail"
  run --separate-stderr v42_keys_rows t
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"listing the vault failed"* && "$stderr" == *401* ]]
}

@test "my_account: the first account id auth me prints; a dead session is status 1" {
  run v42_my_account
  [ "$output" = 7704efb0-5a6a-4117-9cdd-a9265a8fc350 ]
  echo dead >"$FAKE42/session"
  run v42_my_account
  [ "$status" -eq 1 ]
}
