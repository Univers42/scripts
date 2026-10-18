#!/usr/bin/env bash
# vault42.sh — entry point of the vault42 CLI. Resolves its own directory through symlinks, sources
# lib/ and cmd/, parses the global flags and dispatches. Sets no `-e`: every command returns its own
# exit code (0 ok, 1 failed or refused, 2 usage or invalid config, 3 personal vault, 4 locked,
# 5 missing credential).
#
# Caveat: global flags are recognised anywhere on the line, so a command argument that is literally
# `--target` cannot be passed through; none of the commands takes one.

# shellcheck disable=SC2034 # V42_TARGET_FLAG and V42_KINDS are read by lib/targets.sh, which shellcheck checks apart
set -uo pipefail

_v42_self_dir() {
  local src="${BASH_SOURCE[0]}" dir
  while [ -L "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" == /* ]] || src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

V42_HOME="$(_v42_self_dir)"
for _m in common state scan private envfile seedsums lock volumes config creds ctl hooks kinds remote \
  diffs gitignored stage netdiag targets privacy volkey volrows push; do
  # shellcheck source=/dev/null
  . "$V42_HOME/lib/$_m.sh"
done
for _m in help doctor access inventory transfer secret volumes config; do
  # shellcheck source=/dev/null
  . "$V42_HOME/cmd/$_m.sh"
done
unset _m

V42_CONFIG_FLAG=""
V42_TARGET_FLAG=""
V42_KIND_ARGS=()
V42_REST=()

_v42_parse_globals() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --config | --target | --kind)
      [ "$#" -ge 2 ] || {
        usage_error "$1 needs a value"
        return 2
      }
      case "$1" in
      --config) V42_CONFIG_FLAG="$2" ;;
      --target) V42_TARGET_FLAG="$2" ;;
      --kind) V42_KIND_ARGS+=("$2") ;;
      esac
      shift 2
      ;;
    --config=*)
      V42_CONFIG_FLAG="${1#*=}"
      shift
      ;;
    --target=*)
      V42_TARGET_FLAG="${1#*=}"
      shift
      ;;
    --kind=*)
      V42_KIND_ARGS+=("${1#*=}")
      shift
      ;;
    *)
      V42_REST+=("$1")
      shift
      ;;
    esac
  done
}

_v42_dispatch() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
  help | -h | --help) cmd_help "$@" ;;
  doctor | status) cmd_doctor "$@" ;;
  login) cmd_login "$@" ;;
  keys) cmd_keys "$@" ;;
  list) cmd_list "$@" ;;
  diff) cmd_diff "$@" ;;
  find) cmd_find "$@" ;;
  pull) cmd_pull "$@" ;;
  push) cmd_push "$@" ;;
  secret) cmd_secret "$@" ;;
  config) cmd_config "$@" ;;
  volumes) cmd_volumes "$@" ;;
  *) usage_error "unknown command '$cmd'; run: vault42 help" ;;
  esac
}

main() {
  _v42_parse_globals "$@" || return 2
  case "${V42_REST[0]:-help}" in help | -h | --help)
    _v42_dispatch "${V42_REST[@]}"
    return
    ;;
  esac
  read -ra V42_KINDS <<<"$(v42_kinds_select "${V42_KIND_ARGS[@]}")" || return 2
  V42_CONFIG_RC=0
  v42_config_load "$(v42_config_path "$V42_CONFIG_FLAG")" || V42_CONFIG_RC=$?
  case "${V42_REST[0]}" in
  doctor | status) ;;
  *) [ "$V42_CONFIG_RC" -eq 0 ] || return "$V42_CONFIG_RC" ;;
  esac
  _v42_dispatch "${V42_REST[@]}"
}

main "$@"
exit $?
