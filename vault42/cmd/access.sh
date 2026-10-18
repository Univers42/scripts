# shellcheck shell=bash
# access.sh — `vault42 login` and `vault42 keys ls`. Defines functions only; sourced by vault42.sh.
#
# login signs in with the credentials of the ENVIRONMENT: FT_EMAIL (42ctl reads it as FT_LOGIN_EMAIL),
# FT_PASSWORD and FT_TENANT. Nothing is read from a file or asked on a terminal.
#
# Caveat: FT_TENANT has no 42ctl environment variable, so the tenant name travels in argv as
# `--tenant NAME`; it is a name, not a secret. Caveat (assumption A3): `--password` is passed bare and
# 42ctl is trusted to read FT_PASSWORD from its environment; untested against a live 42ctl.

cmd_login() {
  local what
  for what in passphrase password email tenant; do
    v42_cred_require "$what" || return 5
  done
  if v42_ctl login auth login --password --tenant "$(v42_cred tenant)"; then
    note "signed in"
  else
    note "login failed: check FT_EMAIL, FT_PASSWORD and FT_TENANT; 42ctl said the lines above"
    return 1
  fi
}

cmd_keys() {
  local t rows
  [ "${1:-ls}" = ls ] || {
    usage_error "usage: vault42 keys ls"
    return 2
  }
  v42_cred_require passphrase || return 5
  v42_scoped_targets || return 2
  for t in "${V42_SEL[@]}"; do
    rows="$(v42_keys_rows "$t")" || return 1
    printf '[%s]\n%s\n' "$t" "$rows"
  done
}
