#!/usr/bin/env bats
# login, keys ls, list, diff, find, secret, config show and the entry script's own behaviour.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  proj_setup
  printf '4 a.env\n4 secrets/k.env\n5 old.env\n' >"$FAKE42/files.e"
  printf 'secrets/k.env\n' >"$FAKE42/private.e"
}

teardown() { assert_no_stdin_violation; }

@test "help lists every command and exits 0" {
  run "$V42" help
  [ "$status" -eq 0 ]
  for c in doctor login list diff pull push find secret config volumes; do [[ "$output" == *"  $c"* ]]; done
}

@test "help CMD describes one command; an unknown topic exits 2" {
  run "$V42" help push
  [ "$status" -eq 0 ]
  [[ "$output" == *BYTES* ]]
  run "$V42" help nonsense
  [ "$status" -eq 2 ]
}

@test "an unknown command exits 2" {
  run "$V42" frobnicate
  [ "$status" -eq 2 ]
}

@test "the entry resolves its own directory through a symlink" {
  ln -s "$V42" "$BATS_TEST_TMPDIR/vault42"
  run "$BATS_TEST_TMPDIR/vault42" config show
  [ "$status" -eq 0 ]
  [[ "$output" == "[t]"* ]]
}

@test "--config PATH and --target NAME select; an unknown target exits 2" {
  unset VAULT42_CONFIG
  run "$V42" --config "$CONF" --target t config show
  [ "$status" -eq 0 ]
  run "$V42" --config "$CONF" --target nope list
  [ "$status" -eq 2 ]
  run "$V42" --config "$BATS_TEST_TMPDIR/none.conf" list
  [ "$status" -eq 2 ]
}

@test "list shows size, private flag and path" {
  run "$V42" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[t]"* ]]
  [[ "$output" == *"private secrets/k.env"* ]]
  [[ "$output" == *"shared  a.env"* ]]
}

@test "diff shows + - ~ with counts and restores only with --only" {
  printf 'AAAAAA' >"$R/a.env"
  run "$V42" diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"~ a.env 6->4 bytes"* ]]
  [[ "$output" == *"- old.env"* ]]
  [[ "$output" == *"vault42 pull --apply --only old.env"* ]]
  run grep -c 'pull --apply$' <<<"$output"
  [ "$output" = 0 ]
}

@test "find matches a glob and a bare substring across the vault" {
  run "$V42" find '*.env'
  [[ "$output" == *$'t\told.env'* ]]
  run "$V42" find k.e
  [ "$output" = $'t\tsecrets/k.env' ]
}

@test "keys ls prints each target's holders" {
  run "$V42" keys ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"other active"* ]]
}

@test "secret set reads stdin, get prints it; a value never enters argv" {
  printf 'sv-planted-9999' | "$V42" secret set infra/X
  run "$V42" secret get infra/X
  [ "$output" = sv-planted-9999 ]
  run grep -c 'sv-planted-9999' "$FAKE42/argv.log"
  [ "$output" = 0 ]
}

@test "secret with a bad action exits 2" {
  run "$V42" secret frob x
  [ "$status" -eq 2 ]
}

@test "login signs in from the environment alone" {
  export FT_PASSWORD=pw-planted-3333 FT_EMAIL=em-planted-4444@example.test FT_TENANT=univers42
  run "$V42" login
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE42/session")" = alive ]
  run grep -c 'pw-planted-3333\|em-planted-4444' "$FAKE42/argv.log"
  [ "$output" = 0 ]
}

@test "login: aliases FT_LOGIN_EMAIL work when FT_EMAIL is unset" {
  export FT_PASSWORD=pw-planted-3333 FT_LOGIN_EMAIL=em@example.test FT_TENANT=univers42
  run "$V42" login
  [ "$status" -eq 0 ]
}

@test "login without a password exits 5 and names FT_PASSWORD" {
  export FT_EMAIL=e@example.test FT_TENANT=univers42
  run --separate-stderr "$V42" login
  [ "$status" -eq 5 ]
  [[ "$stderr" == *FT_PASSWORD* ]]
}

@test "login failure exits 1 and never prints the password" {
  export FT_PASSWORD=pw-planted-3333 FT_EMAIL=e@example.test FT_TENANT=univers42
  touch "$FAKE42/login-fail"
  run "$V42" login
  [ "$status" -eq 1 ]
  run grep -c pw-planted-3333 <<<"$output"
  [ "$output" = 0 ]
}

@test "C2: CI variables leave config show byte-identical" {
  "$V42" config show >"$BATS_TEST_TMPDIR/before"
  VAULT42_SESSION_B64=zzz VAULT42_CI=1 FT_S3_KEY=k run "$V42" config show
  [ "$output" = "$(cat "$BATS_TEST_TMPDIR/before")" ]
}
