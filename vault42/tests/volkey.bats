#!/usr/bin/env bats
# `guard = sole-holder` on a volumes target: the push is refused unless the env exists under its exact
# name, nobody else holds the key and the operator's wrap unwraps; a pass is followed by a restore
# drill whose marker lives under the git common dir (C12), never in the checkout (C15).
bats_require_minimum_version 1.5.0

load helpers/common

ME=7704efb0-5a6a-4117-9cdd-a9265a8fc350

setup() {
  fakes_setup
  R="$(make_repo)"
  mkdir -p "$R/secrets"
  chmod 700 "$R/secrets"
  printf 'dump-bytes' >"$R/secrets/volume-pg_data.tar.gz"
  write_conf "$R" 'kinds = volumes' 'guard = sole-holder' 'min_free_mb = 1' 'private = secrets/volume-*.tar.gz'
  export VAULT42_CONFIG="$CONF" FT_PASSPHRASE=pass-planted-1111
  V42="$V42_ROOT_DIR/vault42.sh"
  printf '%s active\n' "$ME" >"$FAKE42/keys.e"
}

marker() { printf '%s/.git/vault42/drilled.o.p.e' "$R"; }

@test "sole holder: the push goes through, the drill passes and the marker is written under .git" {
  run "$V42" --kind volumes push --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"restore drill: the vault gives back every pushed file"* ]]
  [ -s "$(marker)" ]
  run find "$R" -path "$R/.git" -prune -o -name '*drilled*' -print
  [ "$output" = "" ]
}

@test "another active holder refuses the push before anything is sent" {
  printf 'other active\n' >>"$FAKE42/keys.e"
  run "$V42" --kind volumes push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"also held by [other]"* ]]
  [ ! -s "$FAKE42/push.log" ]
}

@test "an env that does not exist under its exact name refuses and creates nothing" {
  printf 'e2 other-env\n' >"$FAKE42/envs"
  run "$V42" --kind volumes push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"no env named exactly 'e'"* ]]
  [ ! -s "$FAKE42/push.log" ]
  run grep -c 'env init\|keys sync' "$FAKE42/argv.log"
  [ "$output" = 0 ]
}

@test "a wrap that does not unwrap refuses (the first listing already fails; the proof is a second line)" {
  : >"$FAKE42/files.e"
  : >"$FAKE42/nowrap.e"
  run "$V42" --kind volumes push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"no wrap for this account"* ]]
  [ ! -s "$FAKE42/push.log" ]
}

@test "a drilled env that now holds no tree was re-keyed and refuses" {
  "$V42" --kind volumes push --yes
  rm -f "$FAKE42/files.e"
  rm -rf "$FAKE42/tree.e" "$FAKE42/push.log"
  printf 'changed' >"$R/secrets/volume-pg_data.tar.gz"
  run "$V42" --kind volumes push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"re-keyed"* ]]
  [ ! -s "$FAKE42/push.log" ]
}

@test "a drill that finds a difference exits 1 and writes no marker" {
  : >"$FAKE42/pull-fail"
  run "$V42" --kind volumes push --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"restore drill: pull --apply failed"* ]]
  [ ! -e "$(marker)" ]
}
