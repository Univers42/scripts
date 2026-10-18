#!/usr/bin/env bats
# lib/state.sh alone. C12: every tool state file sits under <git common dir>/vault42/, from a
# plain repo, a linked worktree and a submodule. C4: the scratch dir is mode 700 under
# <git common dir>/vault42-tmp/ and is removed on EXIT, INT, TERM and HUP.

bats_require_minimum_version 1.5.0

setup() {
  LIB="$BATS_TEST_DIRNAME/../lib/state.sh"
  . "$LIB"
  R="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$R"
  git -C "$R" init -q
  git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
}

@test "C12: a plain repository keeps its state under .git/vault42" {
  run v42_state_dir "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "$R/.git/vault42" ]
  [ "$(stat -c %a "$R/.git/vault42")" = 700 ]
}

@test "C12: a linked worktree shares the main repository's state dir" {
  git -C "$R" worktree add -q "$BATS_TEST_TMPDIR/wt2"
  run v42_state_dir "$BATS_TEST_TMPDIR/wt2"
  [ "$status" -eq 0 ]
  [ "$output" = "$R/.git/vault42" ]
}

@test "C12: a submodule keeps its state under the superproject's .git/modules" {
  local sub="$BATS_TEST_TMPDIR/sub"
  git init -q "$sub"
  git -C "$sub" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
  git -C "$R" -c protocol.file.allow=always submodule add -q "$sub" apps/sub
  run v42_state_dir "$R/apps/sub"
  [ "$status" -eq 0 ]
  [ "$output" = "$R/.git/modules/apps/sub/vault42" ]
}

@test "C12: outside git the state dir is ROOT/.vault42" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run v42_state_dir "$BATS_TEST_TMPDIR/plain"
  [ "$output" = "$BATS_TEST_TMPDIR/plain/.vault42" ]
}

# Runs v42_mktmp in its own process and prints the directory, then LEAVE decides how it ends.
tmp_run() {
  bash -c '. "$1"; v42_mktmp "$2"; printf "%s\n" "$V42_TMP" >"$3"; echo "mode=$(stat -c %a "$V42_TMP")"; '"$1" _ "$LIB" "$R" "$BATS_TEST_TMPDIR/tmpdir"
}

@test "C4: the scratch dir is mode 700 under <git common dir>/vault42-tmp, never /tmp" {
  run tmp_run 'true'
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=700"* ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/tmpdir")" == "$R/.git/vault42-tmp/"* ]]
  [ "$(stat -c %a "$R/.git/vault42-tmp")" = 700 ]
}

@test "C4: the scratch dir is removed on a normal EXIT" {
  run tmp_run 'true'
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/tmpdir")" ]
}

@test "C4: the scratch dir is removed on a failing EXIT" {
  run tmp_run 'exit 7'
  [ "$status" -eq 7 ]
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/tmpdir")" ]
}

@test "C4: the scratch dir is removed on INT, TERM and HUP" {
  local sig
  for sig in INT TERM HUP; do
    run tmp_run "kill -$sig \$\$; sleep 5"
    [ "$status" -ne 0 ]
    [ ! -e "$(cat "$BATS_TEST_TMPDIR/tmpdir")" ]
  done
}

@test "v42_on_exit runs registered functions last-in first-out" {
  run bash -c '. "$1"; a() { echo a; }; b() { echo b; }; v42_on_exit a; v42_on_exit b' _ "$LIB"
  [ "$output" = $'b\na' ]
}
