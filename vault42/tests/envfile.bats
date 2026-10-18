#!/usr/bin/env bats
# lib/envfile.sh alone: get_env reads the same plain KEY=VALUE line a stack file holds.
bats_require_minimum_version 1.5.0

setup() {
  . "$BATS_TEST_DIRNAME/../lib/envfile.sh"
  F="$BATS_TEST_TMPDIR/x.stack"
  printf '# c\nA=1\n  B = 2\nA=old-dup\nQ="two words"\nE=\nX=a=b\n#H=zz\n' >"$F"
}

@test "get_env: first live value, blanks around name and value dropped, '=' in the value kept" {
  [ "$(get_env "$F" A)" = 1 ]
  [ "$(get_env "$F" B)" = 2 ]
  [ "$(get_env "$F" X)" = "a=b" ]
}

@test "get_env: one pair of surrounding quotes is stripped" {
  [ "$(get_env "$F" Q)" = "two words" ]
}

@test "get_env: a commented-out, empty or absent key, or a missing file, prints nothing and exits 1" {
  local k
  for k in H E NOPE; do
    run get_env "$F" "$k"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
  done
  run get_env "$BATS_TEST_TMPDIR/none" A
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
