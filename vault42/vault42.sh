#!/usr/bin/env bash
# vault42.sh — entry point of the vault42 CLI. Resolves its own directory through symlinks, sources
# lib/ and cmd/, parses the global flags and dispatches. Sets no `-e`: every command returns its own
# exit code (0 ok, 1 failed or refused, 2 usage or invalid config, 3 personal vault, 4 locked,
# 5 missing credential).
#
# Caveat: global flags are recognised anywhere on the line, so a command argument that is literally
# `--target` cannot be passed through; none of the commands takes one.

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
  diffs gitignored stage netdiag push; do
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

# v42_pick_targets: V42_SEL = the --target, or every target; status 2 on an unknown name.
v42_pick_targets() {
  V42_SEL=()
  if [ -z "$V42_TARGET_FLAG" ]; then
    mapfile -t V42_SEL < <(v42_targets)
    return 0
  fi
  local marker="$V42_TARGET_FLAG."
  if [ -z "${V42_CFG[$marker]+x}" ]; then
    usage_error "no target '$V42_TARGET_FLAG' in the config; targets: $(v42_targets | paste -sd' ')"
    return 2
  fi
  V42_SEL=("$V42_TARGET_FLAG")
}

# v42_scoped_targets: V42_SEL narrowed to the targets the selected kinds touch; status 2 when none.
v42_scoped_targets() {
  local t
  local -a kept=()
  v42_pick_targets || return 2
  for t in "${V42_SEL[@]}"; do
    [ "$(v42_kind_scope "$t" $V42_KINDS)" = none ] || kept+=("$t")
  done
  V42_SEL=("${kept[@]}")
  [ "${#V42_SEL[@]}" -gt 0 ] || usage_error "no target holds the selected kinds ($V42_KINDS); see: vault42 config show"
}

# v42_single_target: V42_T = the one target a state-changing command acts on; status 2 when ambiguous.
v42_single_target() {
  v42_scoped_targets || return 2
  if [ "${#V42_SEL[@]}" -ne 1 ]; then
    usage_error "this command acts on one target; pick one with --target (${V42_SEL[*]})"
    return 2
  fi
  V42_T="${V42_SEL[0]}"
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
  V42_KINDS="$(v42_kinds_select "${V42_KIND_ARGS[@]}")" || return 2
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
