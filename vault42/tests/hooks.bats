#!/usr/bin/env bats
# lib/hooks.sh alone (C3): hooks are exec'd as argv, never through a shell; a hook file must be
# tracked, outside secrets/ and the scan; the credentials a hook sees are the level's and no more.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  . "$BATS_TEST_DIRNAME/../lib/common.sh"
  . "$BATS_TEST_DIRNAME/../lib/creds.sh"
  . "$BATS_TEST_DIRNAME/../lib/scan.sh"
  . "$BATS_TEST_DIRNAME/../lib/hooks.sh"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/scripts"
  git -C "$R" init -q
  printf '#!/bin/sh\nenv >"%s/seen"\n' "$BATS_TEST_TMPDIR" >"$R/scripts/hook.sh"
  git -C "$R" add scripts/hook.sh
}

plant() {
  export FT_PASSPHRASE=PLANT-pass FT_PASSWORD=PLANT-pw FT_EMAIL=PLANT-mail FT_TENANT=PLANT-tenant VAULT42_REGISTER_TOKEN=PLANT-token
}

@test "C3: a hook is exec'd as argv, so \$(…) in an argument is a literal" {
  # The external printf (hooks never run builtins) warns about the excess argument on stderr.
  run --separate-stderr v42_hook_run "$R" "printf '\$(touch x)'" none
  [ "$status" -eq 0 ]
  [ "$output" = "'\$(touch" ]
  [ ! -e "$R/x" ]
  [ ! -e x ]
}

@test "C3: shell syntax in a hook is not interpreted" {
  run v42_hook_run "$R" 'echo a ; touch semi | cat > redirected' none
  [ "$status" -eq 0 ]
  [ "$output" = 'a ; touch semi | cat > redirected' ]
  [ ! -e "$R/semi" ] && [ ! -e "$R/redirected" ]
}

@test "C3: the hook runs with cwd at the root and its own status comes back" {
  git -C "$R" add -N scripts/hook.sh
  printf '#!/bin/sh\npwd >"%s/cwd"\nexit 7\n' "$BATS_TEST_TMPDIR" >"$R/scripts/hook.sh"
  run v42_hook_run "$R" 'sh scripts/hook.sh' none
  [ "$status" -eq 7 ]
  [ "$(cat "$BATS_TEST_TMPDIR/cwd")" = "$(cd "$R" && pwd -P)" ]
}

@test "C3: post_pull sees FT_PASSPHRASE and none of the other four" {
  plant
  run v42_hook_run "$R" 'sh scripts/hook.sh' hook
  [ "$status" -eq 0 ]
  run grep -c PLANT-pass "$BATS_TEST_TMPDIR/seen"
  [ "$output" = 1 ]
  for v in PLANT-pw PLANT-mail PLANT-tenant PLANT-token; do
    run grep -c "$v" "$BATS_TEST_TMPDIR/seen"
    [ "$output" = 0 ]
  done
}

@test "C3: pre_push sees no credential at all" {
  plant
  run v42_hook_run "$R" 'sh scripts/hook.sh' none
  [ "$status" -eq 0 ]
  run grep -c PLANT "$BATS_TEST_TMPDIR/seen"
  [ "$output" = 0 ]
}

@test "C3: a hook file that git does not track exits 2 before anything runs" {
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" >"$R/scripts/loose.sh"
  run --separate-stderr v42_hook_run "$R" 'sh scripts/loose.sh' none
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"not tracked"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "C3: a hook file under secrets/ exits 2 even when tracked" {
  mkdir -p "$R/secrets"
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" >"$R/secrets/hook.sh"
  git -C "$R" add -f secrets/hook.sh
  run --separate-stderr v42_hook_run "$R" 'sh secrets/hook.sh' none
  [ "$status" -eq 2 ]
  [[ "$stderr" == *secrets* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "C3: a hook file the scan would upload exits 2 even when tracked" {
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" >"$R/scripts/hook.env.sh"
  git -C "$R" add scripts/hook.env.sh
  run --separate-stderr v42_hook_run "$R" 'sh scripts/hook.env.sh' none
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"scan would upload"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "C3: a symlinked hook file and one outside the root exit 2" {
  ln -s hook.sh "$R/scripts/link.sh"
  git -C "$R" add scripts/link.sh
  run --separate-stderr v42_hook_run "$R" 'sh scripts/link.sh' none
  [ "$status" -eq 2 ]
  [[ "$stderr" == *symlink* ]]
  printf '#!/bin/sh\n' >"$BATS_TEST_TMPDIR/outside.sh"
  run --separate-stderr v42_hook_run "$R" "sh $BATS_TEST_TMPDIR/outside.sh" none
  [ "$status" -eq 2 ]
  [[ "$stderr" == *outside* ]]
}

@test "an empty hook is a successful no-op" {
  run v42_hook_run "$R" '' none
  [ "$status" -eq 0 ]
}

# A hook's first word must be a file on disk: a builtin or keyword would run inside the CLI's own
# shell, where the passphrase/password/email/token locals of v42_with_creds are still in scope.
@test "C3: a builtin or keyword as the first word is refused or blind to the CLI's variables" {
  plant
  printf 'declare -p password >"%s/peek" 2>&1\n' "$BATS_TEST_TMPDIR" >"$R/scripts/peek.sh"
  git -C "$R" add scripts/peek.sh
  local hook first
  for hook in 'declare -p password' 'builtin declare -p password' 'command declare -p password' \
    '. scripts/peek.sh' 'source scripts/peek.sh' 'eval declare${IFS}-p${IFS}password'; do
    rm -f "$BATS_TEST_TMPDIR/peek"
    run v42_hook_run "$R" "$hook" hook
    first="${hook%% *}"
    if [ -z "$(type -P "$first")" ]; then [ "$status" -eq 2 ]; fi
    [[ "$output" != *PLANT-pw* ]]
    [ ! -e "$BATS_TEST_TMPDIR/peek" ] || ! grep -q PLANT-pw "$BATS_TEST_TMPDIR/peek"
  done
}

@test "C3: eval cannot assemble a command word out of the hook's characters" {
  run v42_hook_run "$R" 'eval $(touch${IFS}x)' none
  [ "$status" -eq 2 ]
  [ ! -e "$R/x" ] && [ ! -e x ]
}

@test "C3: a hook that is a tracked executable file still runs, and sees only its level" {
  plant
  printf '#!/bin/sh\nenv >"%s/seen"\n' "$BATS_TEST_TMPDIR" >"$R/scripts/run.sh"
  chmod +x "$R/scripts/run.sh"
  git -C "$R" add scripts/run.sh
  run v42_hook_run "$R" scripts/run.sh hook
  [ "$status" -eq 0 ]
  run grep -c PLANT-pass "$BATS_TEST_TMPDIR/seen"
  [ "$output" = 1 ]
  run grep -c PLANT-pw "$BATS_TEST_TMPDIR/seen"
  [ "$output" = 0 ]
}

@test "C3: the CI session, keystore and contract blobs never reach a hook" {
  export VAULT42_SESSION_B64=PLANT-sess VAULT42_KEYSTORE_B64=PLANT-ks VAULT42_CONTRACT_B64=PLANT-ct
  run v42_hook_run "$R" 'sh scripts/hook.sh' hook
  [ "$status" -eq 0 ]
  run grep -c PLANT "$BATS_TEST_TMPDIR/seen"
  [ "$output" = 0 ]
}
