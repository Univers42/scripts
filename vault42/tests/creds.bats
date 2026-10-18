#!/usr/bin/env bats
# lib/creds.sh alone: environment-only credentials, alias fallback, and which of the five a child
# of each level can see. The "planted value" tests are the leak mutation check: a unique value is
# put in every variable and must be absent from a child that is not entitled to it.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  . "$BATS_TEST_DIRNAME/../lib/creds.sh"
}

plant() {
  export FT_PASSPHRASE=PLANT-pass FT_PASSWORD=PLANT-pw FT_EMAIL=PLANT-mail FT_TENANT=PLANT-tenant VAULT42_REGISTER_TOKEN=PLANT-token
  export FT_S3_KEY=PLANT-s3k FT_S3_SECRET=PLANT-s3s
}

# seen LEVEL — what a child of LEVEL sees of the planted values, one file.
seen() { v42_with_creds "$1" env >"$BATS_TEST_TMPDIR/seen"; }

count() {
  run grep -c "$1" "$BATS_TEST_TMPDIR/seen"
  echo "$output"
}

@test "canonical name wins over its alias, the alias is used when the canonical is unset" {
  FT_PASSPHRASE=canon VAULT42_PASSPHRASE=alias run v42_cred passphrase
  [ "$output" = canon ]
  VAULT42_PASSPHRASE=alias run v42_cred passphrase
  [ "$output" = alias ]
  VAULT42_PASSPHRASE=alias run v42_cred_name passphrase
  [ "$output" = VAULT42_PASSPHRASE ]
  FT_LOGIN_EMAIL=a@b run v42_cred email
  [ "$output" = a@b ]
  FT_REGISTER_TOKEN=t run v42_cred token
  [ "$output" = t ]
}

@test "C7: no passphrase is status 5 and stderr names FT_PASSPHRASE" {
  run --separate-stderr v42_cred_require passphrase
  [ "$status" -eq 5 ]
  [[ "$stderr" == *FT_PASSPHRASE* ]]
  VAULT42_PASSPHRASE=x run v42_cred_require passphrase
  [ "$status" -eq 0 ]
}

@test "no credential file is read: a file present and the environment unset is still 5" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/42ctl"
  printf 'FT_PASSPHRASE=from-file\n' >"$HOME/.config/42ctl/secret"
  run --separate-stderr v42_cred_require passphrase
  [ "$status" -eq 5 ]
  [[ "$stderr" == *FT_PASSPHRASE* ]]
  [ -z "$(v42_cred passphrase)" ]
}

@test "level none: a child sees none of the five" {
  plant
  seen none
  [ "$(count PLANT)" = 0 ]
}

@test "level hook: a child sees the passphrase and nothing else (C3)" {
  plant
  seen hook
  [ "$(count PLANT-pass)" = 1 ]
  for v in PLANT-pw PLANT-mail PLANT-tenant PLANT-token PLANT-s3k PLANT-s3s; do
    [ "$(count "$v")" = 0 ]
  done
}

@test "level keystore: passphrase and S3 key, not password, email, tenant or token" {
  plant
  seen keystore
  [ "$(count PLANT-pass)" = 1 ]
  [ "$(count PLANT-s3k)" = 1 ]
  for v in PLANT-pw PLANT-mail PLANT-tenant PLANT-token; do
    [ "$(count "$v")" = 0 ]
  done
}

@test "level login: email arrives as FT_LOGIN_EMAIL only; tenant and token never" {
  plant
  seen login
  [ "$(count '^FT_LOGIN_EMAIL=PLANT-mail')" = 1 ]
  [ "$(count '^FT_EMAIL=')" = 0 ]
  [ "$(count '^FT_PASSWORD=PLANT-pw')" = 1 ]
  [ "$(count PLANT-tenant)" = 0 ]
  [ "$(count PLANT-token)" = 0 ]
}

@test "level register: the token arrives as FT_REGISTER_TOKEN only" {
  plant
  seen register
  [ "$(count '^FT_REGISTER_TOKEN=PLANT-token')" = 1 ]
  [ "$(count '^VAULT42_REGISTER_TOKEN=')" = 0 ]
}

@test "an alias supplies the value under 42ctl's spelling" {
  VAULT42_PASSPHRASE=via-alias seen keystore
  [ "$(count '^FT_PASSPHRASE=via-alias')" = 1 ]
  [ "$(count '^VAULT42_PASSPHRASE=')" = 0 ]
}

@test "a value never appears in the child's argv" {
  plant
  v42_with_creds login bash -c 'tr "\0" " " </proc/$$/cmdline' >"$BATS_TEST_TMPDIR/seen"
  [ "$(count PLANT)" = 0 ]
}

@test "an unknown level is refused" {
  run v42_with_creds nonsense true
  [ "$status" -eq 2 ]
}
