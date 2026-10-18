#!/usr/bin/env bats
# lib/config.sh alone: INI parsing without evaluation, validation, defaults, and the C2 rule that
# only known (target,key) pairs are read from the environment.
bats_require_minimum_version 1.5.0

setup() {
  . "$BATS_TEST_DIRNAME/../lib/config.sh"
  D="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$D"
  cd "$D"
  for n in $(env | sed -n 's/^\(VAULT42_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$n"; done
}

# conf TEXT... — write ./vault42.conf from the arguments, one line each.
conf() { printf '%s\n' "$@" >"$D/vault42.conf"; }

base() {
  conf '[secrets]' 'org = univers42' 'project = groot' 'env = prod'
}

@test "parse: sections, comments, inline comments, defaults" {
  conf '# top comment' '; another' '' '[secrets]  ; first target' \
    'org = univers42' 'project = groot   ; the project' 'env = prod' \
    'private = vendor/* secrets/*.env' '' '[volumes]' 'org=u' 'project=g' 'env=volumes' 'kinds = volumes'
  v42_config_load "$D/vault42.conf"
  [ "$(v42_targets)" = $'secrets\nvolumes' ]
  [ "$(v42_cfg secrets project)" = groot ]
  [ "$(v42_cfg secrets private)" = 'vendor/* secrets/*.env' ]
  [ "$(v42_cfg secrets kinds)" = 'env secrets' ]
  [ "$(v42_cfg secrets mode)" = team ]
  [ "$(v42_cfg secrets min_free_mb)" = 1024 ]
  [ "$(v42_cfg secrets refuse_on_env)" = 'staging prod' ]
  [ "$(v42_cfg secrets personal_fallback)" = no ]
  [ "$(v42_cfg volumes kinds)" = volumes ]
}

@test "parse: private patterns are words, never globbed against the working directory" {
  mkdir -p vendor && touch vendor/a
  conf '[s]' 'org = o' 'project = p' 'env = e' 'private = vendor/* secrets/*.env'
  v42_config_load "$D/vault42.conf"
  [ "$(v42_cfg_private s)" = $'vendor/*\nsecrets/*.env' ]
}

@test "parse: a value is never evaluated" {
  conf '[s]' 'org = o' 'project = p' 'env = e' "pre_push = printf '\$(touch pwned)'"
  v42_config_load "$D/vault42.conf"
  [ "$(v42_cfg s pre_push)" = "printf '\$(touch pwned)'" ]
  [ ! -e pwned ]
}

@test "parse: relative root and stage_dir resolve against the config's directory" {
  mkdir -p sub
  conf '[s]' 'org = o' 'project = p' 'env = e' 'root = ..' 'stage_dir = out'
  cd "$BATS_TEST_TMPDIR"
  v42_config_load "$D/vault42.conf"
  [ "$(v42_cfg s root)" = "$BATS_TEST_TMPDIR" ]
  [ "$(v42_cfg s stage_dir)" = "$D/out" ]
}

@test "invalid: every malformed config exits 2 naming file:line or the target" {
  local bad
  for bad in \
    '[s]|org = o|project = p|env = e|colour = red' \
    'org = o|[s]' \
    '[s]|org = o|project = p|env = e|just words' \
    '[s]|org = o|project = p' \
    '[s]|org = o;rm|project = p|env = e' \
    '[s]|org = o|project = p|env = e|mode = both' \
    '[s]|org = o|project = p|env = e|kinds = env nonsense' \
    '[s]|org = o|project = p|env = e|kinds = volumes env' \
    '[s]|org = o|project = p|env = e|min_free_mb = lots' \
    '[s]|org = o|project = p|env = e|personal_fallback = maybe' \
    '[s]|org = o|project = p|env = e|[s]' \
    '# nothing'; do
    IFS='|' read -ra lines <<<"$bad"
    conf "${lines[@]}"
    run --separate-stderr v42_config_load "$D/vault42.conf"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *vault42* ]]
  done
  run --separate-stderr v42_config_load "$D/missing.conf"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no such file"* ]]
}

@test "invalid: an unknown key names its line" {
  conf '[s]' 'org = o' 'project = p' 'env = e' 'colour = red'
  run --separate-stderr v42_config_load "$D/vault42.conf"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"vault42.conf:5"* && "$stderr" == *colour* ]]
}

@test "path: --config beats VAULT42_CONFIG beats ./vault42.conf" {
  [ "$(v42_config_path)" = ./vault42.conf ]
  export VAULT42_CONFIG=/env/path
  [ "$(v42_config_path)" = /env/path ]
  [ "$(v42_config_path /flag/path)" = /flag/path ]
}

@test "C2: min_free_mb can only be raised from the environment" {
  conf '[s]' 'org = o' 'project = p' 'env = e' 'min_free_mb = 2000'
  VAULT42_S_MIN_FREE_MB=5000 v42_config_load "$D/vault42.conf"
  [ "$(v42_cfg s min_free_mb)" = 5000 ]
  VAULT42_S_MIN_FREE_MB=10 run --separate-stderr v42_config_load "$D/vault42.conf"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"may only raise"* ]]
  VAULT42_S_MIN_FREE_MB=10 v42_config_load "$D/vault42.conf" 2>/dev/null
  [ "$(v42_cfg s min_free_mb)" = 2000 ]
}

@test "C2: private_add adds patterns and never removes the configured ones" {
  conf '[s]' 'org = o' 'project = p' 'env = e' 'private = vendor/*'
  VAULT42_S_PRIVATE_ADD='extra/*' v42_config_load "$D/vault42.conf"
  [ "$(v42_cfg_private s)" = $'vendor/*\nextra/*' ]
}

@test "C2: VAULT42_<TARGET>_PRIVATE= and PRE_PUSH= change nothing" {
  conf '[secrets]' 'org = o' 'project = p' 'env = e' 'private = vendor/*' 'pre_push = true'
  v42_config_load "$D/vault42.conf"
  v42_config_show >"$BATS_TEST_TMPDIR/before"
  VAULT42_SECRETS_PRIVATE= VAULT42_SECRETS_PRE_PUSH=true VAULT42_SECRETS_GUARD= VAULT42_SECRETS_KINDS=volumes \
    VAULT42_SECRETS_REFUSE_ON_ENV= VAULT42_SECRETS_PERSONAL_FALLBACK=yes v42_config_load "$D/vault42.conf"
  v42_config_show >"$BATS_TEST_TMPDIR/after"
  cmp "$BATS_TEST_TMPDIR/before" "$BATS_TEST_TMPDIR/after"
}

@test "C2: CI's VAULT42_* variables leave config show byte-identical" {
  conf '[secrets]' 'org = o' 'project = p' 'env = e' 'private = vendor/*' '[session]' 'org = o' 'project = p' 'env = x'
  v42_config_load "$D/vault42.conf"
  v42_config_show >"$BATS_TEST_TMPDIR/before"
  VAULT42_SESSION_B64=aaa VAULT42_KEYSTORE_B64=bbb VAULT42_CONTRACT_B64=ccc VAULT42_SOURCE=ci VAULT42_ANYTHING=1 \
    VAULT42_SESSION_ORG=hijack v42_config_load "$D/vault42.conf"
  v42_config_show >"$BATS_TEST_TMPDIR/after"
  cmp "$BATS_TEST_TMPDIR/before" "$BATS_TEST_TMPDIR/after"
  [ -s "$BATS_TEST_TMPDIR/before" ]
}

@test "C2: root and stage_dir may be overridden from the environment" {
  mkdir -p elsewhere
  base
  VAULT42_SECRETS_ROOT="$D/elsewhere" VAULT42_SECRETS_STAGE_DIR=/x/stage v42_config_load "$D/vault42.conf"
  [ "$(v42_cfg secrets root)" = "$D/elsewhere" ]
  [ "$(v42_cfg secrets stage_dir)" = /x/stage ]
}

@test "show: effective settings in a fixed key order" {
  base
  v42_config_load "$D/vault42.conf"
  run v42_config_show
  [ "$output" = $'[secrets]\norg = univers42\nproject = groot\nenv = prod\nroot = '"$D"$'\nkinds = env secrets\nmode = team\nrefuse_on_env = staging prod\nmin_free_mb = 1024\npersonal_fallback = no' ]
}

# `./u.secrets` never equals the stored path `u.secrets`, so the archive of every git-ignored file
# once went out shared while the privacy verify passed.
@test "C1: an archive path with ./, .., // or a leading / is rejected at load, naming the key" {
  local key bad
  for key in stage_unscanned_as stage_dir_as; do
    for bad in ./u.secrets ../u.secrets a/../u.secrets a//u.secrets /abs/u.secrets a/./u.secrets a/ ..; do
      conf '[s]' 'org = o' 'project = p' 'env = e' "$key = $bad"
      run --separate-stderr v42_config_load "$D/vault42.conf"
      [ "$status" -eq 2 ]
      [[ "$stderr" == *"$key"* ]]
    done
  done
  conf '[s]' 'org = o' 'project = p' 'env = e' 'stage_unscanned_as = secrets/u.tgz' 'stage_dir_as = a/b.tgz'
  v42_config_load "$D/vault42.conf"
}
