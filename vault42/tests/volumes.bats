#!/usr/bin/env bats
# lib/volumes.sh alone: docker volumes as files. docker is a fake that models each volume as a
# directory and runs the entrypoint (tar, sh) on the host with the container paths (/v, /out, /s)
# mapped to host dirs, so the archives are real. Every docker argv is logged to $FAKE_DOCKER/argv.log.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  export V42_MIN_FREE_MB=1
  . "$BATS_TEST_DIRNAME/../lib/volumes.sh"
  . "$BATS_TEST_DIRNAME/../lib/scan.sh"
}

mkvol() { mkdir -p "$FAKE_DOCKER/volumes/$1"; }

filled_volume() {
  mkvol "$1"
  mkdir -p "$FAKE_DOCKER/volumes/$1/sub/deep"
  echo one >"$FAKE_DOCKER/volumes/$1/a.txt"
  echo two >"$FAKE_DOCKER/volumes/$1/sub/deep/b.txt"
  echo dot >"$FAKE_DOCKER/volumes/$1/.hidden"
}

docker_runs() { grep -c '^run ' "$FAKE_DOCKER/argv.log" || true; }

@test "all five cache suffixes are caches" {
  for n in x_gobuild x-gomod a-cargo-home pnpm_store node_modules proj_node_modules; do
    volume_is_cache "$n"
  done
}

@test "volume_is_cache splits 17 real host volume names into exactly the 7 caches" {
  local caches="agent-a5c7fab22a64206f5_playground_node_modules agent-a5c7fab22a64206f5_playground_pnpm_store mini-baas-gobuild mini-baas-gomod track-binocle_drawnosaurus-cargo-home wt-osionos-abac_playground_node_modules wt-osionos-abac_playground_pnpm_store"
  local data="agent-a5c7fab22a64206f5_mongodb_data mini-baas_minio-data mini-baas_mongo-data mini-baas_mongo-keyfile mini-baas_mysql-data mini-baas_postgres-data mini-baas_redis-data mini-baas_sqlite-data track-binocle_drawnosaurus-mongo-data wt-osionos-abac_mongodb_data"
  local n got=""
  for n in $caches $data; do
    ! volume_is_cache "$n" || got="$got $n"
  done
  [ "${got# }" = "$caches" ]
}

@test "a near-miss name is not a cache" {
  run volume_is_cache my-gomodx
  [ "$status" -eq 1 ]
  run volume_is_cache mini-baas_postgres-data
  [ "$status" -eq 1 ]
}

@test "data_volumes lists only non-cache non-empty volumes, sorted" {
  filled_volume zeta-data
  filled_volume alpha-data
  mkvol empty-data
  filled_volume proj_gobuild
  mkdir -p "$FAKE_DOCKER/volumes/dotonly" && : >"$FAKE_DOCKER/volumes/dotonly/.x"
  run data_volumes
  [ "$status" -eq 0 ]
  [ "$output" = $'alpha-data\ndotonly\nzeta-data' ]
}

many_volumes() {
  local i
  for i in $(seq -w 1 12); do
    case "$i" in
    03 | 05 | 11) mkvol "vol-$i" ;;
    *) filled_volume "vol-$i" ;;
    esac
  done
  filled_volume cache_gobuild
}

@test "data_volumes checks 12 volumes in a single container (/v/1 is not /v/10)" {
  many_volumes
  run data_volumes
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'vol-%s\n' 01 02 04 06 07 08 09 10 12)" ]
  [ "$(docker_runs)" -eq 1 ]
}

@test "data_volumes with no non-cache volume prints nothing and starts no container" {
  run data_volumes
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  filled_volume only_gobuild
  run data_volumes
  [ -z "$output" ]
  run grep -c '^run ' "$FAKE_DOCKER/argv.log"
  [ "$output" = 0 ]
}

@test "data_volumes falls back to one container per volume when the batch fails" {
  many_volumes
  FAKE_BATCH_FAIL=1 run --separate-stderr data_volumes
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'vol-%s\n' 01 02 04 06 07 08 09 10 12)" ]
  [[ "$stderr" == *"one by one"* ]]
  [ "$(docker_runs)" -eq 13 ]
}

@test "volume_users prints only the containers mounting that volume" {
  printf 'c1 vol-a\nc2 vol-b\nc3 vol-a\n' >"$FAKE_DOCKER/ps"
  run volume_users vol-a
  [ "$output" = $'c1\nc3' ]
  run volume_users vol-z
  [ -z "$output" ]
}

@test "archive round trip keeps nested files and dotfiles" {
  filled_volume vol-a
  volume_archive vol-a "$BATS_TEST_TMPDIR/out"
  mkdir "$BATS_TEST_TMPDIR/x"
  tar -C "$BATS_TEST_TMPDIR/x" -xzf "$BATS_TEST_TMPDIR/out/volume-vol-a.tar.gz"
  diff -r "$FAKE_DOCKER/volumes/vol-a" "$BATS_TEST_TMPDIR/x"
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out" | grep '^\.')" ]
}

@test "volume_archive_name renames .bak and a trailing .stale, leaves other dots" {
  [ "$(volume_archive_name vol-a)" = volume-vol-a.tar.gz ]
  [ "$(volume_archive_name x.bak_d)" = volume-x_bak_d.tar.gz ]
  [ "$(volume_archive_name a.bak.bak)" = volume-a_bak_bak.tar.gz ]
  [ "$(volume_archive_name x.stale)" = volume-x_stale.tar.gz ]
  [ "$(volume_archive_name x.stale.y)" = volume-x.stale.y.tar.gz ]
}

@test "a volume named x.bak_d is archived under a name the scanner lists" {
  filled_volume x.bak_d
  mkdir -p "$BATS_TEST_TMPDIR/root/secrets"
  volume_archive x.bak_d "$BATS_TEST_TMPDIR/root/secrets"
  [ -f "$BATS_TEST_TMPDIR/root/secrets/volume-x_bak_d.tar.gz" ]
  run vault42_scan "$BATS_TEST_TMPDIR/root"
  [ "$output" = "secrets/volume-x_bak_d.tar.gz" ]
}

@test "during tar the tmp name ends .stale and the scanner does not list it" {
  filled_volume vol-a
  mkdir -p "$BATS_TEST_TMPDIR/root/secrets"
  FAKE_TAR_FAIL=1 run volume_archive vol-a "$BATS_TEST_TMPDIR/root/secrets"
  [ "$status" -eq 1 ]
  [[ "$(cat "$FAKE_DOCKER/tmpname")" == *.stale ]]
  echo partial >"$BATS_TEST_TMPDIR/root/secrets/$(cat "$FAKE_DOCKER/tmpname")"
  run vault42_scan "$BATS_TEST_TMPDIR/root"
  [ -z "$output" ]
}

@test "the archive is mode 600" {
  filled_volume vol-a
  volume_archive vol-a "$BATS_TEST_TMPDIR/out"
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/out/volume-vol-a.tar.gz")" = 600 ]
}

@test "an archive below the free-space floor is refused with status 2 before docker runs" {
  filled_volume vol-a
  V42_MIN_FREE_MB=999999999 run volume_archive vol-a "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 2 ]
  [[ "$output" == *floor* ]]
  [ "$(docker_runs)" -eq 0 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
}

@test "a failing tar returns 1 and leaves no tmp or archive behind" {
  filled_volume vol-a
  FAKE_TAR_FAIL=1 run volume_archive vol-a "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 1 ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
}

@test "restore into a new volume recreates the tree" {
  filled_volume vol-a
  volume_archive vol-a "$BATS_TEST_TMPDIR/out"
  volume_restore "$BATS_TEST_TMPDIR/out/volume-vol-a.tar.gz" vol-b
  diff -r "$FAKE_DOCKER/volumes/vol-a" "$FAKE_DOCKER/volumes/vol-b"
}

@test "restore into a non-empty volume is refused without V42_FORCE=1" {
  filled_volume vol-a
  volume_archive vol-a "$BATS_TEST_TMPDIR/out"
  mkvol vol-b
  echo keep >"$FAKE_DOCKER/volumes/vol-b/mine"
  run volume_restore "$BATS_TEST_TMPDIR/out/volume-vol-a.tar.gz" vol-b
  [ "$status" -eq 1 ]
  [[ "$output" == *V42_FORCE=1* ]]
  [ "$(ls -A "$FAKE_DOCKER/volumes/vol-b")" = mine ]
  V42_FORCE=1 volume_restore "$BATS_TEST_TMPDIR/out/volume-vol-a.tar.gz" vol-b
  [ -f "$FAKE_DOCKER/volumes/vol-b/sub/deep/b.txt" ]
  [ -f "$FAKE_DOCKER/volumes/vol-b/mine" ]
}

@test "restore of a corrupt or missing archive is refused before any docker call" {
  echo not-gzip >"$BATS_TEST_TMPDIR/out/bad.tar.gz"
  run volume_restore "$BATS_TEST_TMPDIR/out/bad.tar.gz" vol-b
  [ "$status" -eq 1 ]
  run volume_restore "$BATS_TEST_TMPDIR/out/absent.tar.gz" vol-b
  [ "$status" -eq 1 ]
  [ ! -s "$FAKE_DOCKER/argv.log" ]
}

@test "every docker run carries --network none" {
  filled_volume vol-a
  volume_archive vol-a "$BATS_TEST_TMPDIR/out"
  volume_restore "$BATS_TEST_TMPDIR/out/volume-vol-a.tar.gz" vol-b
  data_volumes >/dev/null
  [ "$(docker_runs)" -ge 4 ]
  [ "$(grep -c '^run .*--network none' "$FAKE_DOCKER/argv.log")" -eq "$(docker_runs)" ]
}
