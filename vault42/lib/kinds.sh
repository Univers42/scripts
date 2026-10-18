# shellcheck shell=bash
# kinds.sh — which parts of a target a command acts on. Sourced; sets no shell options; needs
# config.sh, private.sh and common.sh.
#
#   v42_kinds_select ARG…       normalise --kind arguments (env|secrets|volumes|all) to a word list;
#                               none given -> "env secrets" (volumes are never implied); status 2
#                               on an unknown kind.
#   v42_kind_patterns KIND      the 42ctl `--only` patterns of KIND (none for volumes: a volumes target
#                               is selected whole)
#   v42_kind_scope TARGET KIND… full | partial | none: do the selected kinds cover all, some or
#                               none of the target's kinds
#   v42_kind_only TARGET KIND…  the `--only` patterns that restrict a pull to the selected kinds; nothing
#                               when the scope is full
#   v42_kind_require_full TARGET KIND…
#                               status 2 unless the scope is full: `env push` REPLACES the vault's
#                               whole tree, so a push of part of a target would delete the rest
#   v42_path_in_kinds PATH KIND…  status 0 when PATH belongs to one of the kinds
#
# Caveat: the patterns are the scanner's file-name rules (scan.sh), so a path counts as `secrets` by
# directory name alone; a file matching both lists belongs to both kinds.

V42_KIND_ALL="env secrets volumes"
V42_KIND_ENV_PATTERNS='*.env*'
V42_KIND_SECRETS_PATTERNS='secrets/* */secrets/* .secrets/* */.secrets/* *.secrets'

v42_kinds_select() {
  local kind picked=""
  for kind in "$@"; do
    case "$kind" in
    all) picked="$picked $V42_KIND_ALL" ;;
    env | secrets | volumes) picked="$picked $kind" ;;
    *)
      usage_error "--kind takes env, secrets, volumes or all, not '$kind'"
      return 2
      ;;
    esac
  done
  [ -n "$picked" ] || picked="env secrets"
  printf '%s' "$picked" | tr -s ' ' '\n' | awk 'NF && !seen[$0]++' | paste -sd' '
}

v42_kind_patterns() {
  case "$1" in
  env) printf '%s\n' "$V42_KIND_ENV_PATTERNS" ;;
  secrets) tr ' ' '\n' <<<"$V42_KIND_SECRETS_PATTERNS" ;;
  esac
}

# Prints the target's kinds that are also selected, space separated.
_v42_kind_common() {
  local target="$1" kind own
  shift
  for kind in $(v42_cfg "$target" kinds); do
    for own; do [ "$own" != "$kind" ] || printf '%s ' "$kind"; done
  done
}

v42_kind_scope() {
  local target="$1"
  local -a common total
  shift
  read -ra common <<<"$(_v42_kind_common "$target" "$@")"
  read -ra total <<<"$(v42_cfg "$target" kinds)"
  if [ "${#common[@]}" -eq 0 ]; then
    printf none
  elif [ "${#common[@]}" -eq "${#total[@]}" ]; then
    printf full
  else
    printf partial
  fi
}

v42_kind_only() {
  local target="$1" kind
  [ "$(v42_kind_scope "$@")" = partial ] || return 0
  for kind in $(_v42_kind_common "$@"); do v42_kind_patterns "$kind"; done
}

v42_kind_require_full() {
  [ "$(v42_kind_scope "$@")" = partial ] || return 0
  note "refusing: '$1' holds kinds $(v42_cfg "$1" kinds), and a push replaces the vault's whole tree, so a push of only '${*:2}' would delete the rest. Push without --kind (or with every kind of the target)."
  return 2
}

v42_path_in_kinds() {
  local path="$1" kind pattern
  shift
  for kind; do
    while IFS= read -r pattern; do
      ! vault42_glob_match "$path" "$pattern" || return 0
    done < <(v42_kind_patterns "$kind")
  done
  return 1
}
