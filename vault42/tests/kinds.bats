#!/usr/bin/env bats
# lib/kinds.sh alone: the --kind selection, its --only patterns, and C6 (a partial-kind push of a
# multi-kind target is refused; a pull of one kind is fine).
bats_require_minimum_version 1.5.0

setup() {
  . "$BATS_TEST_DIRNAME/../lib/common.sh"
  . "$BATS_TEST_DIRNAME/../lib/config.sh"
  . "$BATS_TEST_DIRNAME/../lib/private.sh"
  . "$BATS_TEST_DIRNAME/../lib/kinds.sh"
  cd "$BATS_TEST_TMPDIR"
  printf '%s\n' '[both]' 'org = o' 'project = p' 'env = e' '[envonly]' 'org = o' 'project = p' 'env = x' 'kinds = env' \
    '[vols]' 'org = o' 'project = p' 'env = v' 'kinds = volumes' >vault42.conf
  v42_config_load vault42.conf
}

@test "select: default is env secrets, never volumes; all is every kind; duplicates collapse" {
  [ "$(v42_kinds_select)" = "env secrets" ]
  [ "$(v42_kinds_select all)" = "env secrets volumes" ]
  [ "$(v42_kinds_select env env secrets)" = "env secrets" ]
  [ "$(v42_kinds_select volumes)" = volumes ]
}

@test "select: an unknown kind is a usage error" {
  run --separate-stderr v42_kinds_select nonsense
  [ "$status" -eq 2 ]
  [[ "$stderr" == *nonsense* ]]
}

@test "scope: full, partial or none against the target's kinds" {
  [ "$(v42_kind_scope both env secrets)" = full ]
  [ "$(v42_kind_scope both env)" = partial ]
  [ "$(v42_kind_scope both volumes)" = none ]
  [ "$(v42_kind_scope envonly env secrets)" = full ]
  [ "$(v42_kind_scope envonly secrets)" = none ]
  [ "$(v42_kind_scope vols env secrets)" = none ]
  [ "$(v42_kind_scope vols volumes)" = full ]
}

@test "leaves_out: true only when the target holds the kind and the selection skips it" {
  v42_kind_leaves_out both env secrets
  v42_kind_leaves_out both env volumes
  run v42_kind_leaves_out both env env secrets
  [ "$status" -eq 1 ]
  run v42_kind_leaves_out vols env env secrets
  [ "$status" -eq 1 ]
  run v42_kind_leaves_out envonly secrets env
  [ "$status" -eq 1 ]
}

@test "C6: pull of one kind maps to --only patterns; a full selection maps to none" {
  run v42_kind_only both env
  [ "$output" = '*.env*' ]
  run v42_kind_only both secrets
  [ "$output" = $'secrets/*\n*/secrets/*\n.secrets/*\n*/.secrets/*\n*.secrets' ]
  run v42_kind_only both env secrets
  [ -z "$output" ]
}

@test "C6: a push of a partial kind of a multi-kind target exits 2" {
  run --separate-stderr v42_kind_require_full both env
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"replaces the vault's whole tree"* ]]
  run v42_kind_require_full both env secrets
  [ "$status" -eq 0 ]
  run v42_kind_require_full envonly env secrets
  [ "$status" -eq 0 ]
}

@test "path_in_kinds: env files and secrets files belong to their kind" {
  v42_path_in_kinds app/.env.local env
  v42_path_in_kinds secrets/key.pem secrets
  v42_path_in_kinds a/secrets/k secrets
  v42_path_in_kinds prod.secrets secrets
  run v42_path_in_kinds secrets/key.pem env
  [ "$status" -eq 1 ]
  run v42_path_in_kinds app/.env secrets
  [ "$status" -eq 1 ]
}
