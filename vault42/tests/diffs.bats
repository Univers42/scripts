#!/usr/bin/env bats
# lib/diffs.sh alone: the size diff, the bytes-and-mode diff (C4) and the kind restriction.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  load_lib common state scan private config creds ctl kinds remote diffs
  R="$(make_repo)"
  write_conf "$R"
  v42_config_load "$CONF"
  export FT_PASSPHRASE=x
  mkdir -p "$R/secrets" "$FAKE42/tree.e/secrets"
  printf 'aaaa' >"$R/a.env"
  printf 'bbbb' >"$R/secrets/k.pem"
  printf 'aaaa' >"$FAKE42/tree.e/a.env"
  printf 'bbbb' >"$FAKE42/tree.e/secrets/k.pem"
  printf '4 a.env\n4 secrets/k.pem\n' >"$FAKE42/files.e"
}

teardown() { assert_no_stdin_violation; }

@test "table: identical trees give an empty diff" {
  run v42_diff_table t env secrets
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "table: added, dropped and size-changed files carry + - ~" {
  printf 'new' >"$R/n.env"
  printf 'longer' >"$R/a.env"
  printf '4 gone.env\n' >>"$FAKE42/files.e"
  run v42_diff_table t env secrets
  [ "$status" -eq 0 ]
  [ "$output" = $'~ a.env 6->4 bytes\n- gone.env\n+ n.env' ]
}

@test "table: a vault that cannot be read is a failure, not an empty diff" {
  touch "$FAKE42/files-fail"
  run v42_diff_table t env secrets
  [ "$status" -eq 1 ]
}

@test "table: a vault holding no tree counts everything as added" {
  rm "$FAKE42/files.e"
  run v42_diff_table t env secrets
  [ "$output" = $'+ a.env\n+ secrets/k.pem' ]
}

@test "counts: summarise the table" {
  run v42_diff_counts $'+ a\n+ b\n- c\n~ d x'
  [ "$output" = "2 added, 1 dropped, 1 changed" ]
}

@test "exact: equal size, different bytes is a change the size diff cannot see" {
  printf 'cccc' >"$R/a.env"
  run v42_diff_table t env secrets
  [ -z "$output" ]
  run v42_diff_exact t env secrets
  [ "$status" -eq 0 ]
  [ "$output" = '~ a.env bytes' ]
}

@test "exact: a mode change is a change" {
  chmod 600 "$R/a.env"
  chmod 644 "$FAKE42/tree.e/a.env"
  run v42_diff_exact t env secrets
  [ "$output" = '~ a.env mode 644->600' ]
}

@test "exact: identical bytes and mode give nothing; added and dropped are marked" {
  chmod 644 "$R/a.env" "$R/secrets/k.pem" "$FAKE42/tree.e/a.env" "$FAKE42/tree.e/secrets/k.pem"
  run v42_diff_exact t env secrets
  [ -z "$output" ]
  printf 'x' >"$R/n.env"
  printf 'x' >"$FAKE42/tree.e/old.env"
  run v42_diff_exact t env secrets
  [ "$output" = $'+ n.env\n- old.env' ]
}

@test "exact: the scratch restore is mode 700 under the git common dir and is gone after the process" {
  run bash -c ". '$V42_ROOT_DIR/lib/common.sh'; . '$V42_ROOT_DIR/lib/state.sh'; . '$V42_ROOT_DIR/lib/scan.sh'; . '$V42_ROOT_DIR/lib/private.sh'; . '$V42_ROOT_DIR/lib/config.sh'; . '$V42_ROOT_DIR/lib/creds.sh'; . '$V42_ROOT_DIR/lib/ctl.sh'; . '$V42_ROOT_DIR/lib/kinds.sh'; . '$V42_ROOT_DIR/lib/remote.sh'; . '$V42_ROOT_DIR/lib/diffs.sh'; v42_config_load '$CONF'; v42_diff_exact t env secrets; stat -c %a \"\$V42_TMP\"; echo \"\$V42_TMP\" >'$BATS_TEST_TMPDIR/tmpdir'"
  [ "$status" -eq 0 ]
  [[ "$output" == *700 ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/tmpdir")" == "$R/.git/vault42-tmp/"* ]]
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/tmpdir")" ]
}

@test "exact: a restore that fails is a failure" {
  touch "$FAKE42/pull-fail"
  run v42_diff_exact t env secrets
  [ "$status" -eq 1 ]
}

@test "kinds: a partial selection limits both sides" {
  write_conf "$R" "kinds = env secrets"
  v42_config_load "$CONF"
  printf 'zz' >"$R/secrets/extra.pem"
  run v42_diff_table t env
  [ -z "$output" ]
  run v42_diff_table t secrets
  [ "$output" = '+ secrets/extra.pem' ]
}

@test "row path: the path of every row shape, without the size or mode suffix" {
  [ "$(v42_diff_row_path '~ a.env 5->4 bytes')" = a.env ]
  [ "$(v42_diff_row_path '~ dir/a b.env bytes')" = 'dir/a b.env' ]
  [ "$(v42_diff_row_path '~ a.env mode 644->600')" = a.env ]
  [ "$(v42_diff_row_path '+ x/y')" = x/y ]
  [ "$(v42_diff_row_path '- x/y')" = x/y ]
  run v42_diff_row_path 'restore with:'
  [ "$status" -eq 1 ]
}
