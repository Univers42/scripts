#!/usr/bin/env bats
# `vault42 push` refusals found by the strict review: archive paths, nested secrets, re-sealing,
# team-only flags on the personal routes, lock failures and the byte compare outside git.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  proj_setup
}

teardown() { assert_no_stdin_violation; }

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

@test "lock: a state dir that cannot be created is exit 1 with the cause, not 4 (locked)" {
  : >"$R/.git/vault42"
  run --separate-stderr "$V42" push --yes
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE42/push.log" ]
}

@test "C4: a file push outside git is refused: the scratch dir would sit inside the scanned tree" {
  local plain="$BATS_TEST_TMPDIR/plain"
  mkdir -p "$plain"
  printf 'AAAA' >"$plain/a.env"
  printf 'BBBB' >"$plain/b.env"
  sed -i "s|^root = .*|root = $plain|" "$CONF"
  run --separate-stderr "$V42" push --yes b.env
  [ "$status" -eq 1 ]
  [[ "$stderr" == *git* ]]
  [ ! -e "$plain/.vault42-tmp" ]
  [ ! -e "$FAKE42/push.log" ]
}
