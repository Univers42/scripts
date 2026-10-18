# shellcheck shell=bash
# secret.sh — `vault42 secret get|set PATH`: one value in the vault's secret store. Defines functions
# only; sourced by vault42.sh.
#
# `get` prints the value on stdout because that is its job; `set` reads the value from stdin so it
# never appears in argv.

cmd_secret() {
  local action="${1:-}" path="${2:-}"
  case "$action" in get | set) ;; *)
    usage_error "usage: vault42 secret get PATH | vault42 secret set PATH < value"
    return 2
    ;;
  esac
  [ -n "$path" ] || {
    usage_error "vault42 secret $action needs a PATH"
    return 2
  }
  v42_cred_require passphrase || return 5
  v42_single_target || return 2
  v42_envargs "$V42_T"
  if [ "$action" = get ]; then
    _v42_in_root "$V42_T" keystore env secret get "${V42_ENVARGS[@]}" "$path"
  else
    (cd "$(v42_cfg "$V42_T" root)" && v42_ctl_feed keystore env secret set "${V42_ENVARGS[@]}" "$path")
  fi
}
