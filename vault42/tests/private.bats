#!/usr/bin/env bats
# lib/private.sh alone: 42ctl's glob, the private filter, and the secrets/ files no rule classifies.
bats_require_minimum_version 1.5.0

setup() {
  . "$BATS_TEST_DIRNAME/../lib/private.sh"
}

@test "glob: * is the only wildcard and it crosses a slash" {
  vault42_glob_match secrets/grobase-certs.tar.gz 'secrets/*cert*'
  vault42_glob_match a/b/c.local '*.local'
  vault42_glob_match secrets/.vault42-admin.env 'secrets/.*'
  vault42_glob_match .env.grobase-remote .env.grobase-remote
  run vault42_glob_match secrets/dylan.envx 'secrets/*.env'
  [ "$status" -eq 1 ]
  run vault42_glob_match xsecrets/a.env 'secrets/*.env'
  [ "$status" -eq 1 ]
}

@test "glob: ? and [ are literal characters, as in 42ctl" {
  vault42_glob_match 'a?b' 'a?b'
  run vault42_glob_match axb 'a?b'
  [ "$status" -eq 1 ]
  vault42_glob_match 'a[x]' 'a[x]'
  run vault42_glob_match ax 'a[x]'
  [ "$status" -eq 1 ]
}

@test "filter: *.local is private without being listed; a non-match is dropped" {
  run vault42_filter_private $'vendor/*\nsecrets/*.env' <<<$'.env.local\nvendor/x/.env\nsecrets/a.env\nsecrets/b.dump\nplain.env'
  [ "$output" = $'.env.local\nvendor/x/.env\nsecrets/a.env' ]
}

@test "filter: a pattern is never expanded against the working directory" {
  cd "$BATS_TEST_TMPDIR" && mkdir vendor && touch vendor/x
  run vault42_filter_private 'vendor/*' <<<$'vendor/y'
  [ "$output" = vendor/y ]
}

@test "undecided: only a secrets/ file no private and no shared pattern covers" {
  run vault42_undecided 'secrets/*.env' $'# not a pattern\nsecrets/postgres-all.sql.gz' <<<$'secrets/my_vault\nsecrets/postgres-all.sql.gz\nsecrets/dylan.env\nnot-secrets/odd\n.env\nsecrets/sub/deep.bin'
  [ "$output" = $'secrets/my_vault\nsecrets/sub/deep.bin' ]
}

@test "undecided: an empty shared list decides nothing" {
  run vault42_undecided '' '' <<<$'secrets/a\nsecrets/b.local'
  [ "$output" = secrets/a ]
}

@test "undecided: a secrets or .secrets directory at any depth is covered by the guard" {
  run vault42_undecided 'secrets/*.env' '' <<<$'apps/grobase/secrets/jwt.key\n.secrets/x\na/.secrets/y\nsecrets-old/z\nnot-secrets/odd\napps/secrets'
  [ "$output" = $'apps/grobase/secrets/jwt.key\n.secrets/x\na/.secrets/y' ]
}
