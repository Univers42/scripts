#!/usr/bin/env bats
# lib/stage.sh and lib/gitignored.sh alone.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  load_lib common scan config creds gitignored stage
  R="$(make_repo)"
  git -C "$R" config user.email t@example.test
  git -C "$R" config user.name t
  printf 'secrets/*.tgz\n.stale-*\ncache.dump\nbig.dump\nconf-out/\n' >"$R/.gitignore"
  printf 'x' >"$R/keep.txt"
  git -C "$R" add -A
  git -C "$R" commit -qm init
}

@test "git: an ignored path is ignored, a tracked or unknown one is not" {
  printf d >"$R/cache.dump"
  run is_git_ignored "$R/cache.dump"
  [ "$status" -eq 0 ]
  run is_git_ignored "$R/keep.txt"
  [ "$status" -eq 1 ]
}

@test "git: a path whose directory does not exist yet is judged by the nearest repository" {
  run git_owner_of "$R/secrets/deep/new.tgz"
  [ "$output" = "$R" ]
  run is_git_ignored "$R/secrets/new.tgz"
  [ "$status" -eq 0 ]
}

@test "stage: git-ignored files outside the scan land in a mode-600 archive" {
  printf 'data' >"$R/cache.dump"
  write_conf "$R" "stage_unscanned_as = secrets/extra.tgz"
  v42_config_load "$CONF"
  run v42_stage t
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$R/secrets/extra.tgz")" = 600 ]
  run tar -tzf "$R/secrets/extra.tgz"
  [ "$output" = cache.dump ]
  [ ! -e "$R/secrets/.extra.tgz.stale" ]
}

@test "stage: an archive path git would take is refused" {
  printf 'data' >"$R/cache.dump"
  write_conf "$R" "stage_unscanned_as = extra.tgz"
  v42_config_load "$CONF"
  run v42_stage t
  [ "$status" -eq 1 ]
  [[ "$output" == *"git would take it"* ]]
  [ ! -e "$R/extra.tgz" ]
}

@test "stage: nothing ignored outside the scan means no archive" {
  write_conf "$R" "stage_unscanned_as = secrets/extra.tgz"
  v42_config_load "$CONF"
  run v42_stage t
  [ "$status" -eq 0 ]
  [ ! -e "$R/secrets/extra.tgz" ]
}

@test "stage: an archive over the private ceiling is refused and not left behind" {
  head -c 5000000 /dev/urandom >"$R/big.dump"
  write_conf "$R" "stage_unscanned_as = secrets/extra.tgz"
  v42_config_load "$CONF"
  run v42_stage t
  [ "$status" -eq 1 ]
  [[ "$output" == *"ceiling"* ]]
  [ ! -e "$R/secrets/extra.tgz" ]
  [ ! -e "$R/secrets/.extra.tgz.stale" ]
}

@test "stage: stage_dir files are archived with root-relative paths" {
  mkdir -p "$R/conf-out/sub"
  printf 1 >"$R/conf-out/a.txt"
  printf 2 >"$R/conf-out/sub/b.txt"
  write_conf "$R" "stage_dir = $R/conf-out" "stage_dir_as = secrets/conf.tgz"
  v42_config_load "$CONF"
  run v42_stage t
  [ "$status" -eq 0 ]
  run tar -tzf "$R/secrets/conf.tgz"
  [ "$output" = $'conf-out/a.txt\nconf-out/sub/b.txt' ]
}

@test "stage: the tar child gets no credential" {
  printf 'data' >"$R/cache.dump"
  printf '#!/bin/sh\nenv | grep -c "^FT_PASSPHRASE=" >"%s/tarenv"; exec /bin/tar "$@"\n' "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/bin/tar"
  chmod +x "$BATS_TEST_TMPDIR/bin/tar"
  export FT_PASSPHRASE=planted-pass
  write_conf "$R" "stage_unscanned_as = secrets/extra.tgz"
  v42_config_load "$CONF"
  run v42_stage t
  [ "$(cat "$BATS_TEST_TMPDIR/tarenv")" = 0 ]
}

@test "stale: an unfinished archive under secrets/ is named and refused" {
  mkdir -p "$R/secrets"
  : >"$R/secrets/.extra.tgz.stale"
  run v42_stage_stale "$R"
  [ "$status" -eq 1 ]
  [[ "$output" == *".extra.tgz.stale"* ]]
  rm "$R/secrets/.extra.tgz.stale"
  run v42_stage_stale "$R"
  [ "$status" -eq 0 ]
}

@test "paths: the configured archives" {
  write_conf "$R" "stage_unscanned_as = secrets/a.tgz" "stage_dir_as = secrets/b.tgz"
  v42_config_load "$CONF"
  run v42_stage_paths t
  [ "$output" = $'secrets/a.tgz\nsecrets/b.tgz' ]
}
