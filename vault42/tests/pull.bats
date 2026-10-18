#!/usr/bin/env bats
# `vault42 pull`: preview vs apply, --only from kinds, the space guard, post_pull and G4.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  proj_setup
  "$V42" push --yes >/dev/null 2>&1
  rm -f "$FAKE42/push.log" "$R/b.env"
}

teardown() { assert_no_stdin_violation; }

@test "pull without --apply is a preview and writes nothing" {
  run "$V42" pull
  [ "$status" -eq 0 ]
  [[ "$output" == *"would write b.env"* ]]
  [[ "$output" == *"preview only"* ]]
  [ ! -e "$R/b.env" ]
}

@test "pull --apply restores the missing file" {
  run "$V42" pull --apply
  [ "$status" -eq 0 ]
  [ "$(cat "$R/b.env")" = BBBB ]
}

@test "pull --only restores just that path" {
  rm "$R/a.env"
  run "$V42" pull --apply --only b.env
  [ "$status" -eq 0 ]
  [ -e "$R/b.env" ]
  [ ! -e "$R/a.env" ]
}

@test "C6: pull --kind env is allowed on an env+secrets target and passes the env pattern to --only" {
  run "$V42" --kind env pull
  [ "$status" -eq 0 ]
  grep -q 'argv=env pull .* --only \*\.env\*' "$FAKE42/argv.log"
}

@test "pull of a full-scope target passes no --only" {
  run "$V42" pull
  run grep -c -- '--only' "$FAKE42/argv.log"
  [ "$output" = 0 ]
}

@test "pull without a passphrase exits 5" {
  unset FT_PASSPHRASE
  run --separate-stderr "$V42" pull
  [ "$status" -eq 5 ]
  [[ "$stderr" == *FT_PASSPHRASE* ]]
}

@test "pull --apply refuses when the restore would eat the free-space floor" {
  add_conf "min_free_mb = 999999999"
  run "$V42" pull --apply
  [ "$status" -eq 1 ]
  [ ! -e "$R/b.env" ]
}

@test "pull of an unlisted 42ctl version only warns" {
  echo 0.1.17 >"$FAKE42/version"
  run "$V42" pull
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning"* ]]
}

@test "C3: post_pull runs after --apply with FT_PASSPHRASE only" {
  add_hook after.sh "env | grep -c '^FT_PASSPHRASE=' >'$BATS_TEST_TMPDIR/e1'; env | grep -c '^FT_PASSWORD=' >'$BATS_TEST_TMPDIR/e2'; exit 0"
  add_conf "post_pull = scripts/after.sh"
  export FT_PASSWORD=pw-planted-3333
  run "$V42" pull --apply
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/e1")" = 1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/e2")" = 0 ]
}

@test "post_pull does not run on a preview" {
  add_hook after.sh "touch '$BATS_TEST_TMPDIR/ran'"
  add_conf "post_pull = scripts/after.sh"
  run "$V42" pull
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "G4: a post_pull hook that calls vault42 secret get does not deadlock on the lock" {
  mkdir -p "$FAKE42/secret"
  printf 'sv' >"$FAKE42/secret/X"
  add_hook after.sh "'$V42' secret get X >'$BATS_TEST_TMPDIR/got' 2>'$BATS_TEST_TMPDIR/err'"
  add_conf "post_pull = scripts/after.sh"
  run --separate-stderr "$V42" pull --apply
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/got")" = sv ]
  run grep -c locked "$BATS_TEST_TMPDIR/err"
  [ "$output" = 0 ]
  run grep -c locked <<<"$stderr"
  [ "$output" = 0 ]
}

@test "G4: a post_pull hook that runs a whole pull is not blocked either" {
  add_hook after.sh "'$V42' pull >/dev/null 2>'$BATS_TEST_TMPDIR/err'; echo \$? >'$BATS_TEST_TMPDIR/rc'"
  add_conf "post_pull = scripts/after.sh"
  run "$V42" pull --apply
  [ "$(cat "$BATS_TEST_TMPDIR/rc")" = 0 ]
}

@test "a failing post_pull hook makes pull exit 1 and says the files were restored" {
  add_hook after.sh "exit 7"
  add_conf "post_pull = scripts/after.sh"
  run "$V42" pull --apply
  [ "$status" -eq 1 ]
  [ -e "$R/b.env" ]
}

@test "leak: planted credentials never reach pull's output or 42ctl's argv" {
  export FT_PASSWORD=pw-planted-3333 FT_EMAIL=em-planted-4444@example.test FT_TENANT=tn-planted-5555
  run "$V42" pull --apply
  printf '%s\n' "$output" >"$BATS_TEST_TMPDIR/captured"
  cat "$FAKE42/argv.log" >>"$BATS_TEST_TMPDIR/captured"
  local v
  for v in pass-planted-1111 pw-planted-3333 em-planted-4444 tn-planted-5555; do
    run grep -c "$v" "$BATS_TEST_TMPDIR/captured"
    [ "$output" = 0 ]
  done
}

@test "G7: a root that does not exist fails before any 42ctl call" {
  : >"$FAKE42/argv.log"
  sed -i "s|^root = .*|root = $BATS_TEST_TMPDIR/missing|" "$CONF"
  run "$V42" pull --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/missing"* ]]
  [ ! -s "$FAKE42/argv.log" ]
}
