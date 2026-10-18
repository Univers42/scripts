#!/usr/bin/env bats
# `vault42 push` end to end against the fake 42ctl: C1 C2 C3 C4 C5 C6 C7 C9 C13 C18, the confirm, the
# object-store gate and the credential-leak check.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  proj_setup
}

teardown() { assert_no_stdin_violation; }

pushed() { [ -s "$FAKE42/push.log" ]; }

@test "push --yes on an empty vault pushes, verifies and exits 0" {
  run "$V42" push --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"matches this checkout"* ]]
  [ "$(cat "$FAKE42/files.e" | wc -l)" -eq 3 ]
}

@test "push with nothing different says so and does not push" {
  "$V42" push --yes
  rm "$FAKE42/push.log"
  run "$V42" push --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to push"* ]]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C1: groot's private set, the forced ones and the stage archive are all passed, nothing else" {
  add_conf "stage_unscanned_as = secrets/stage.tgz"
  sed -i "s|^private = .*|private = vendor/* secrets/*.env secrets/*cert* secrets/*key* secrets/.* *.local *.bak .env.grobase-remote|" "$CONF"
  printf 'x' >"$R/cache.dump"
  run "$V42" push --yes
  [ "$status" -eq 0 ]
  got="$(sed 's/^env push //' "$FAKE42/push.log" | tr ' ' '\n' | LC_ALL=C sort | paste -sd' ')"
  want="$(printf '%s\n' 'vendor/*' 'secrets/*.env' 'secrets/*cert*' 'secrets/*key*' 'secrets/.*' '*.local' '*.bak' '.env.grobase-remote' 'secrets/stage.tgz' | LC_ALL=C sort | paste -sd' ')"
  [ "$got" = "$want" ]
}

@test "C1: *.local is private even when the config lists nothing" {
  sed -i '/^private = /d' "$CONF"
  printf 'x' >"$R/x.env.local"
  printf 'KKKK' >"$R/secrets/k.env"
  run "$V42" push --yes --private 'secrets/*.env'
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '\*\.local' "$FAKE42/push.log")" = 1 ]
  grep -qx 'x.env.local' "$FAKE42/private.e"
}

@test "C2: a failing pre_push guard exits 1 and the push never runs" {
  add_hook guard.sh 'exit 1'
  add_conf "pre_push = scripts/guard.sh"
  VAULT42_SECRETS_PRE_PUSH=true run "$V42" push --yes
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C2: VAULT42_SECRETS_PRIVATE= leaves the --private arguments unchanged" {
  "$V42" push --yes
  base="$(cat "$FAKE42/push.log")"
  rm "$FAKE42/push.log"
  printf 'AAAAB' >"$R/a.env"
  VAULT42_SECRETS_PRIVATE= run "$V42" push --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE42/push.log")" = "$base" ]
}

@test "C3: a hook script under secrets/ exits 2 before anything runs" {
  printf '#!/bin/sh\nexit 0\n' >"$R/secrets/guard.sh"
  chmod +x "$R/secrets/guard.sh"
  commit_all "$R"
  add_conf "pre_push = secrets/guard.sh"
  run "$V42" push --yes
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE42/argv.log" ]
}

@test "C3: an untracked hook script exits 2 before anything runs" {
  printf '#!/bin/sh\nexit 0\n' >"$R/scripts/guard.sh"
  chmod +x "$R/scripts/guard.sh"
  add_conf "pre_push = scripts/guard.sh"
  run "$V42" push --yes
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE42/argv.log" ]
}

@test "C3: the pre_push hook runs with no credential in its environment" {
  add_hook guard.sh "env | grep -c '^FT_PASSPHRASE=' >'$BATS_TEST_TMPDIR/hookenv'; exit 0"
  add_conf "pre_push = scripts/guard.sh"
  run "$V42" push --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/hookenv")" = 0 ]
}

@test "C4: file push refuses a same-size different-bytes file and names it" {
  "$V42" push --yes
  printf 'AAAZ' >"$R/a.env"
  printf 'BBBZ' >"$R/b.env"
  rm "$FAKE42/push.log"
  run "$V42" push b.env
  [ "$status" -eq 1 ]
  [[ "$output" == *a.env* ]]
  [[ "$output" == *"vault42 pull --apply --only a.env"* ]]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C4: file push of the one changed file succeeds" {
  "$V42" push --yes
  printf 'BBBZ' >"$R/b.env"
  run "$V42" push --yes b.env
  [ "$status" -eq 0 ]
  cmp "$R/b.env" "$FAKE42/tree.e/b.env"
}

@test "C4: a mode difference on another file also refuses the file push" {
  "$V42" push --yes
  chmod 600 "$R/a.env"
  chmod 644 "$FAKE42/tree.e/a.env"
  printf 'BBBZ' >"$R/b.env"
  run "$V42" push --yes b.env
  [ "$status" -eq 1 ]
  [[ "$output" == *a.env* ]]
}

@test "C4: a named file the scan does not take exits 2" {
  run "$V42" push --yes notes.txt
  [ "$status" -eq 2 ]
}

@test "C4: the restore dir is mode 700 under the git common dir and gone afterwards" {
  "$V42" push --yes
  printf 'BBBZ' >"$R/b.env"
  run "$V42" push --yes b.env
  grep -q "cwd=$R/.git/vault42-tmp/run\.[A-Za-z0-9]*/restore argv=env pull" "$FAKE42/argv.log"
  [ "$(stat -c %a "$R/.git/vault42-tmp")" = 700 ]
  [ -z "$(ls "$R/.git/vault42-tmp")" ]
}

@test "C5: a vault that changes after the review exits 1 with no push" {
  "$V42" push --yes
  rm -f "$FAKE42/push.log"
  touch "$FAKE42/net-flip"
  printf 'AAAAB' >"$R/a.env"
  run "$V42" push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed while you were deciding"* ]]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C5: a drop is refused with an --only fix, never a bare pull --apply" {
  printf '4 gone.env\n' >>"$FAKE42/files.e"
  mkdir -p "$FAKE42/tree.e"
  run "$V42" push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"vault42 pull --apply --only gone.env"* ]]
  run grep -c 'pull --apply$' <<<"$output"
  [ "$output" = 0 ]
}

@test "C5: --drop PATH lets the push replace the tree" {
  printf '4 gone.env\n' >"$FAKE42/files.e"
  run "$V42" push --yes --drop gone.env
  [ "$status" -eq 0 ]
}

@test "C6: push --kind env on an env+secrets target exits 2 and touches nothing" {
  run "$V42" --kind env push --yes
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE42/argv.log" ]
}

@test "C7: push without a passphrase exits 5 naming FT_PASSPHRASE" {
  unset FT_PASSPHRASE
  run --separate-stderr "$V42" push --yes
  [ "$status" -eq 5 ]
  [[ "$stderr" == *FT_PASSPHRASE* ]]
}

@test "C9: an unlisted 42ctl version makes push exit 1 with no push call" {
  echo 0.1.17 >"$FAKE42/version"
  run "$V42" push --yes
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C13: without the config key, --personal and --yes both fail on a key that is not held" {
  printf 'other active\n' >"$FAKE42/keys.e"
  run "$V42" push --yes --personal
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C13: the config key alone, with --yes, does not trigger the personal vault" {
  printf 'other active\n' >"$FAKE42/keys.e"
  add_conf "personal_fallback = yes"
  run "$V42" push --yes
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C13: the config key plus --personal pushes to the personal vault and exits 3" {
  printf 'other active\n' >"$FAKE42/keys.e"
  add_conf "personal_fallback = yes"
  run "$V42" push --yes --personal
  [ "$status" -eq 3 ]
  grep -q 'push --project p' "$FAKE42/push.log"
  [[ "$output" == *PERSONAL* ]]
}

@test "C13: a failed key read never falls back" {
  touch "$FAKE42/keys-fail"
  add_conf "personal_fallback = yes"
  run "$V42" push --yes --personal
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C18: the summary carries the A2 caveat and the active key holders" {
  run "$V42" push --yes
  [[ "$output" == *"files another member pushed private are invisible to you; whether the server keeps them across your push is UNVERIFIED"* ]]
  [[ "$output" == *"active key holders who will read this tree: 7704efb0-5a6a-4117-9cdd-a9265a8fc350 other"* ]]
}

@test "confirm: without --yes and without a terminal, nothing is pushed" {
  VAULT42_TTY=/nonexistent run "$V42" push
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "confirm: y at the terminal pushes, n does not" {
  printf 'n\n' >"$BATS_TEST_TMPDIR/tty"
  VAULT42_TTY="$BATS_TEST_TMPDIR/tty" run "$V42" push
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE42/push.log" ]
  printf 'y\n' >"$BATS_TEST_TMPDIR/tty"
  VAULT42_TTY="$BATS_TEST_TMPDIR/tty" run "$V42" push
  [ "$status" -eq 0 ]
  pushed
}

@test "secrets gate: an undecided secrets/ file refuses, --share decides it" {
  printf 'PEM' >"$R/secrets/x.pem"
  run "$V42" push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *secrets/x.pem* ]]
  run "$V42" push --yes --share secrets/x.pem
  [ "$status" -eq 0 ]
}

@test "S3 gate: a file over the ceiling needs the object-store key from the vault" {
  head -c 4200000 /dev/zero >"$R/big.env"
  run "$V42" push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *infra/S3_KEY* ]]
  mkdir -p "$FAKE42/secret/infra"
  printf 'k' >"$FAKE42/secret/infra/S3_KEY"
  printf 's' >"$FAKE42/secret/infra/S3_SECRET"
  run "$V42" push --yes
  [ "$status" -eq 0 ]
  grep -q 'argv=env push .* s3=yes' "$FAKE42/argv.log"
}

@test "lock: a second run while another holds the lock exits 4" {
  bash -c ". '$V42_ROOT_DIR/lib/common.sh'; . '$V42_ROOT_DIR/lib/state.sh'; . '$V42_ROOT_DIR/lib/lock.sh'; vault42_lock '$R'; sleep 8" &
  sleep 1.5
  run "$V42" push --yes
  kill %1 2>/dev/null || true
  [ "$status" -eq 4 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "G7: a root that does not exist exits non-zero naming it, before any 42ctl call" {
  sed -i "s|^root = .*|root = $BATS_TEST_TMPDIR/missing|" "$CONF"
  run "$V42" push --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/missing"* ]]
  [ ! -s "$FAKE42/argv.log" ]
}

@test "leak: planted credentials never reach output, argv.log or the push log" {
  export FT_PASSWORD=pw-planted-3333 FT_EMAIL=em-planted-4444@example.test FT_TENANT=tn-planted-5555
  run "$V42" push --yes
  printf '%s\n' "$output" >"$BATS_TEST_TMPDIR/captured"
  cat "$FAKE42/argv.log" "$FAKE42/push.log" >>"$BATS_TEST_TMPDIR/captured"
  local v
  for v in pass-planted-1111 pw-planted-3333 em-planted-4444 tn-planted-5555; do
    run grep -c "$v" "$BATS_TEST_TMPDIR/captured"
    [ "$output" = 0 ]
  done
}

@test "C1: an archive path the scan never uploads refuses the push before 42ctl is called" {
  printf 'unscanned.tgz\n' >>"$R/.gitignore"
  printf 'x' >"$R/cache.dump"
  add_conf "stage_unscanned_as = unscanned.tgz"
  run "$V42" push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *unscanned.tgz* ]]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C1: stage_unscanned_as = ./u.secrets is a config error, not a shared archive" {
  printf 'u.secrets\ncache.dump\n' >>"$R/.gitignore"
  printf 'x' >"$R/cache.dump"
  add_conf "stage_unscanned_as = ./u.secrets"
  run "$V42" push --yes
  [ "$status" -eq 2 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "unclassified: a nested secrets/ or .secrets/ file is refused like a top-level one, until decided" {
  mkdir -p "$R/apps/grobase/secrets" "$R/.secrets"
  printf 'JWT' >"$R/apps/grobase/secrets/jwt.key"
  printf 'x' >"$R/.secrets/x"
  run "$V42" push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *apps/grobase/secrets/jwt.key* ]]
  [[ "$output" == *.secrets/x* ]]
  [ ! -e "$FAKE42/push.log" ]
  run "$V42" push --yes --private 'apps/*' --share .secrets/x
  [ "$status" -eq 0 ]
  grep -qx apps/grobase/secrets/jwt.key "$FAKE42/private.e"
  ! grep -qx .secrets/x "$FAKE42/private.e"
}

@test "re-seal: a file already pushed shared and now configured private is pushed, not 'nothing to push'" {
  "$V42" push --yes
  ! grep -qx a.env "$FAKE42/private.e"
  rm -f "$FAKE42/push.log"
  add_conf "private_add = a.env"
  run "$V42" push --yes
  [ "$status" -eq 0 ]
  [ -s "$FAKE42/push.log" ]
  grep -qx a.env "$FAKE42/private.e"
}

@test "team-only flags: personal mode refuses a FILE, --drop, --share and --private with exit 2" {
  add_conf "mode = personal"
  local args
  for args in "b.env" "--drop a.env" "--share x" "--private y"; do
    # shellcheck disable=SC2086 # the word splitting of $args is the point
    run --separate-stderr "$V42" push --yes $args
    [ "$status" -eq 2 ]
    [[ "$stderr" == *personal* ]]
    [ ! -e "$FAKE42/push.log" ]
  done
}

@test "team-only flags: the personal fallback route refuses them too, before pushing" {
  printf 'other active\n' >"$FAKE42/keys.e"
  add_conf "personal_fallback = yes"
  run --separate-stderr "$V42" push --yes --personal b.env
  [ "$status" -eq 2 ]
  [ ! -e "$FAKE42/push.log" ]
}
