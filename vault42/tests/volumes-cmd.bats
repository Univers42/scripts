#!/usr/bin/env bats
# `vault42 volumes list|capture|restore` against the fake docker: C11 (no stop on a staging/prod
# stack), C12 (state under the git common dir, from a linked worktree and a submodule), G7, the space
# guard, restart on failure, and that no credential reaches docker.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  R="$(make_repo)"
  write_conf "$R" 'kinds = volumes' 'min_free_mb = 1'
  export VAULT42_CONFIG="$CONF" FT_PASSPHRASE=pass-planted-1111 TOOLENV_LOG="$BATS_TEST_TMPDIR/toolenv.log"
  V42="$V42_ROOT_DIR/vault42.sh"
  mkvol pg_data
  mkvol redis_data
  mkvol build_gobuild
  printf 'pg' >"$FAKE_DOCKER/volumes/pg_data/PG_VERSION"
  printf 'rd' >"$FAKE_DOCKER/volumes/redis_data/dump.rdb"
  printf 'c1 pg_data\nc2 redis_data\n' >"$FAKE_DOCKER/ps"
}

mkvol() { mkdir -p "$FAKE_DOCKER/volumes/$1"; }
stopped_calls() { grep -c '^stop ' "$FAKE_DOCKER/argv.log" || true; }
running() { sort "$FAKE_DOCKER/ps" | paste -sd' '; }

@test "list shows data volumes with their users and archive state, never a cache" {
  run "$V42" volumes list
  [ "$status" -eq 0 ]
  [[ "$output" == *"pg_data"*"users=c1"*"missing"* ]]
  [[ "$output" == *"2 data volumes, 2 not archived yet"* ]]
  run grep -c gobuild <<<"$output"
  [ "$output" = 0 ]
}

@test "capture --plan names what it would do and stops nothing" {
  run "$V42" volumes capture --plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"would stop [c1 c2]"* ]]
  [ "$(stopped_calls)" -eq 0 ]
  [ ! -e "$R/secrets" ]
}

@test "capture stops the users, archives into secrets/, lists the sums and restarts them" {
  run "$V42" volumes capture
  [ "$status" -eq 0 ]
  [ -s "$R/secrets/volume-pg_data.tar.gz" ]
  [ -s "$R/secrets/volume-redis_data.tar.gz" ]
  run grep -c 'volume-pg_data.tar.gz' "$R/secrets/SHA256SUMS"
  [ "$output" = 1 ]
  [ "$(stat -c %a "$R/secrets")" = 700 ]
  [ "$(running)" = "c1 pg_data c2 redis_data" ]
  [ "$(stopped_calls)" -eq 1 ]
  run "$V42" volumes list
  [[ "$output" == *"archived"* ]]
}

@test "capture --only archives just that volume and rejects an unknown one" {
  run "$V42" volumes capture --only redis_data
  [ "$status" -eq 0 ]
  [ -s "$R/secrets/volume-redis_data.tar.gz" ]
  [ ! -e "$R/secrets/volume-pg_data.tar.gz" ]
  run "$V42" volumes capture --only nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"nope is not a data volume"* ]]
}

@test "a failed archive still restarts every stopped container and leaves no partial file" {
  export FAKE_TAR_FAIL=1
  run "$V42" volumes capture
  [ "$status" -eq 1 ]
  [ "$(running)" = "c1 pg_data c2 redis_data" ]
  run bash -c "ls -A '$R/secrets' | grep -c stale"
  [ "$output" = 0 ]
}

@test "C11: GROBASE_ENV=prod and staging refuse with exit 1 and no docker stop" {
  for stack in prod staging; do
    GROBASE_ENV=$stack run "$V42" volumes capture
    [ "$status" -eq 1 ]
    [[ "$output" == *"GROBASE_ENV=$stack"* ]]
  done
  [ "$(stopped_calls)" -eq 0 ]
  [ "$(running)" = "c1 pg_data c2 redis_data" ]
}

@test "C11: the stack file is read too, and a dev stack is allowed" {
  printf 'GROBASE_ENV=prod\n' >"$BATS_TEST_TMPDIR/stack.env"
  add_conf 'stack_file = stack.env'
  run "$V42" volumes capture
  [ "$status" -eq 1 ]
  [ "$(stopped_calls)" -eq 0 ]
  printf 'GROBASE_ENV=dev\n' >"$BATS_TEST_TMPDIR/stack.env"
  run "$V42" volumes capture
  [ "$status" -eq 0 ]
}

@test "C11: refuse_on_env comes from the config only, an environment variable cannot empty it" {
  VAULT42_REFUSE_ON_ENV= GROBASE_ENV=prod run "$V42" volumes capture
  [ "$status" -eq 1 ]
  [ "$(stopped_calls)" -eq 0 ]
}

@test "the space guard refuses before any container is stopped" {
  add_conf 'min_free_mb = 999999999'
  run "$V42" volumes capture
  [ "$status" -eq 1 ]
  [[ "$output" == *"free"* ]]
  [ "$(stopped_calls)" -eq 0 ]
}

@test "G7: a root that does not exist exits non-zero naming it, before any docker call" {
  sed -i "s|^root = .*|root = $BATS_TEST_TMPDIR/absent|" "$CONF"
  run "$V42" volumes capture
  [ "$status" -ne 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/absent"* ]]
  [ ! -s "$FAKE_DOCKER/argv.log" ]
}

@test "restore round trip: by name, refusing a non-empty volume without --force" {
  "$V42" volumes capture
  rm -rf "$FAKE_DOCKER/volumes/pg_data"
  printf '' >"$FAKE_DOCKER/ps"
  run "$V42" volumes restore pg_data
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_DOCKER/volumes/pg_data/PG_VERSION")" = pg ]
  run "$V42" volumes restore pg_data
  [ "$status" -eq 1 ]
  [[ "$output" == *"not empty"* ]]
  run "$V42" volumes restore --force pg_data
  [ "$status" -eq 0 ]
}

@test "restore --all unpacks every archive and refuses a volume a container is using" {
  "$V42" volumes capture
  rm -rf "$FAKE_DOCKER/volumes/pg_data" "$FAKE_DOCKER/volumes/redis_data"
  printf 'c9 redis_data\n' >"$FAKE_DOCKER/ps"
  run "$V42" volumes restore --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"in use by a running container"* ]]
  [ "$(cat "$FAKE_DOCKER/volumes/pg_data/PG_VERSION")" = pg ]
}

@test "restore with no argument is a usage error" {
  run "$V42" volumes restore
  [ "$status" -eq 2 ]
}

@test "no credential reaches docker" {
  "$V42" volumes capture
  run grep -c '^docker [1-9]' "$TOOLENV_LOG"
  [ "$output" = 0 ]
  run grep -c '^docker 0' "$TOOLENV_LOG"
  [ "$output" -gt 0 ]
}

# C12 — a killed capture's record is found again from the git common dir, in a linked worktree and
# in a submodule, because that is where the state lives.
killed_capture_record() {
  local common="$1"
  mkdir -p "$common/vault42"
  printf 'c1\n' >"$common/vault42/stopped.t"
  printf 'c1 pg_data\n' >"$FAKE_DOCKER/stopped"
  printf 'c2 redis_data\n' >"$FAKE_DOCKER/ps"
}

@test "C12: a linked worktree reads and clears the record kept in the main git dir" {
  git -C "$R" -c user.email=t@e.test -c user.name=t commit -q --allow-empty -m init
  git -C "$R" worktree add -q "$BATS_TEST_TMPDIR/wt"
  sed -i "s|^root = .*|root = $BATS_TEST_TMPDIR/wt|" "$CONF"
  killed_capture_record "$R/.git"
  run "$V42" volumes capture --plan
  run "$V42" volumes capture --only redis_data
  [ "$status" -eq 0 ]
  [[ "$output" == *"previous capture was killed"* ]]
  [ ! -e "$R/.git/vault42/stopped.t" ]
  [ ! -e "$BATS_TEST_TMPDIR/wt/.git/vault42" ]
  [ "$(running)" = "c1 pg_data c2 redis_data" ]
}

@test "C12: a submodule keeps its record under the superproject's modules dir" {
  sub="$(make_repo "$BATS_TEST_TMPDIR/subsrc")"
  git -C "$sub" -c user.email=t@e.test -c user.name=t commit -q --allow-empty -m init
  git -C "$R" -c protocol.file.allow=always -c user.email=t@e.test -c user.name=t submodule add -q "$sub" vols
  sed -i "s|^root = .*|root = $R/vols|" "$CONF"
  common="$(git -C "$R/vols" rev-parse --absolute-git-dir)"
  killed_capture_record "$common"
  run "$V42" volumes capture --only redis_data
  [ "$status" -eq 0 ]
  [[ "$output" == *"previous capture was killed"* ]]
  [ ! -e "$common/vault42/stopped.t" ]
  [ ! -e "$R/vols/.vault42" ]
}
