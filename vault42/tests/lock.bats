#!/usr/bin/env bats
# lib/lock.sh alone: a second holder is refused with "locked", the lock frees on unlock, and the
# lock file sits in the state dir under the git common dir (shared by worktrees).

bats_require_minimum_version 1.5.0

setup() {
  . "$BATS_TEST_DIRNAME/../lib/state.sh"
  . "$BATS_TEST_DIRNAME/../lib/lock.sh"
  R="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$R"
  git -C "$R" init -q
}

# A fresh process stands in for another run.
second() { bash -c '. "$1"; . "$2"; vault42_lock "$3"' _ "$BATS_TEST_DIRNAME/../lib/state.sh" "$BATS_TEST_DIRNAME/../lib/lock.sh" "$1"; }

@test "a second lock on the same root is refused while the first is held" {
  vault42_lock "$R"
  run --separate-stderr second "$R"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"locked: another vault42 run holds"* ]]
  [[ "$stderr" == *"(pid $$)"* ]]
}

@test "after vault42_unlock_lock a second run succeeds" {
  vault42_lock "$R"
  vault42_unlock_lock
  run second "$R"
  [ "$status" -eq 0 ]
}

@test "a git root keeps its lock in the state dir and records the pid" {
  vault42_lock "$R"
  [ "$(cat "$R/.git/vault42/lock")" = "$$" ]
}

@test "a non-git root uses ROOT/.vault42/lock" {
  local plain="$BATS_TEST_TMPDIR/plain"
  mkdir -p "$plain"
  vault42_lock "$plain"
  [ -f "$plain/.vault42/lock" ]
  run --separate-stderr second "$plain"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"$plain/.vault42/lock"* ]]
}

@test "two worktrees of one repository contend for the same lock" {
  git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
  git -C "$R" worktree add -q "$BATS_TEST_TMPDIR/wt2"
  vault42_lock "$R"
  run --separate-stderr second "$BATS_TEST_TMPDIR/wt2"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"$R/.git/vault42/lock"* ]]
}

@test "a missing flock is a clear refusal" {
  run --separate-stderr bash -c '. "$1"; . "$2"; PATH=/nonexistent; vault42_lock "$3"' _ "$BATS_TEST_DIRNAME/../lib/state.sh" "$BATS_TEST_DIRNAME/../lib/lock.sh" "$R"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"flock"* ]]
}
