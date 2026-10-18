# shellcheck shell=bash
# config.sh — parse vault42.conf into V42_CFG and answer questions about it. Sourced; sets no
# shell options. The file is INI and is only ever READ AS TEXT: no value is expanded, evaluated or
# globbed, so `pre_push = printf '$(touch x)'` stays that literal string.
#
#   v42_config_path FLAG   the config file: FLAG, else $VAULT42_CONFIG, else ./vault42.conf
#   v42_config_load FILE   parse + validate + apply env overrides; status 2 with a message naming
#                          file:line on any problem. Sets V42_TARGETS (file order) and V42_CFG.
#   v42_targets            target names, one per line
#   v42_cfg TARGET KEY     the effective value (defaults applied; empty when unset)
#   v42_cfg_private TARGET `private` plus `private_add`, one pattern per line
#   v42_config_show        every target's effective settings, fixed key order
#
# Environment overrides (ADR 0001, .out-of-scope/vault42-env-override-of-safety-keys.md): only the
# known pairs VAULT42_<TARGET>_{ROOT,STAGE_DIR,MIN_FREE_MB,PRIVATE_ADD} are read, by name. MIN_FREE_MB
# can only raise the floor and PRIVATE_ADD can only add patterns, so no variable can weaken a guard;
# every other key, and every other VAULT42_* variable, is ignored by construction.
#
# Caveat: a relative `root`/`stage_dir` resolves against the config file's directory, but the same
# key set through the environment resolves against the current directory. Caveat: a value cannot
# contain ` ;` (it starts an inline comment) and cannot span lines.

declare -gA V42_CFG=()
declare -ga V42_TARGETS=()

V42_CFG_KEYS="org project env root kinds mode private private_add shared pre_push post_pull
stage_unscanned_as stage_dir stage_dir_as refuse_on_env min_free_mb guard personal_fallback stack_file"

v42_config_path() { printf '%s' "${1:-${VAULT42_CONFIG:-./vault42.conf}}"; }

v42_targets() { [ "${#V42_TARGETS[@]}" -eq 0 ] || printf '%s\n' "${V42_TARGETS[@]}"; }

_v42_cfg_default() {
  case "$1" in
  root) printf . ;;
  kinds) printf 'env secrets' ;;
  mode) printf team ;;
  refuse_on_env) printf 'staging prod' ;;
  min_free_mb) printf 1024 ;;
  personal_fallback) printf no ;;
  esac
}

v42_cfg() {
  local key="$1.$2"
  if [ -n "${V42_CFG[$key]+x}" ]; then printf '%s' "${V42_CFG[$key]}"; else _v42_cfg_default "$2"; fi
}

v42_cfg_private() {
  local line
  for line in "$(v42_cfg "$1" private)" "$(v42_cfg "$1" private_add)"; do
    local -a words
    read -ra words <<<"$line"
    [ "${#words[@]}" -eq 0 ] || printf '%s\n' "${words[@]}"
  done
}

_v42_cfg_err() {
  printf 'vault42: config %s: %s\n' "$1" "$2" >&2
  return 2
}

# One line of the file: a section header, a key, or noise. Echoes nothing; mutates V42_CFG.
_v42_cfg_line() {
  local where="$1" line="$2" key value marker
  line="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$line" || "$line" == '#'* || "$line" == ';'* ]] && return 0
  if [[ "$line" =~ ^\[([A-Za-z0-9_-]+)\][[:space:]]*(\;.*)?$ ]]; then
    V42_CFG_CURRENT="${BASH_REMATCH[1]}"
    marker="$V42_CFG_CURRENT."
    [ -z "${V42_CFG[$marker]+x}" ] || {
      _v42_cfg_err "$where" "target [$V42_CFG_CURRENT] is defined twice"
      return 2
    }
    V42_CFG["$marker"]=1
    V42_TARGETS+=("$V42_CFG_CURRENT")
    return 0
  fi
  [[ "$line" == *=* ]] || {
    _v42_cfg_err "$where" "expected [target] or key = value"
    return 2
  }
  key="${line%%=*}"
  key="${key%"${key##*[![:space:]]}"}"
  value="${line#*=}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%%[[:space:]]\;*}"
  [[ "$value" != \;* ]] || value=""
  value="${value%"${value##*[![:space:]]}"}"
  [ -n "${V42_CFG_CURRENT:-}" ] || {
    _v42_cfg_err "$where" "key '$key' before any [target]"
    return 2
  }
  case " ${V42_CFG_KEYS//$'\n'/ } " in
  *" $key "*) ;;
  *)
    _v42_cfg_err "$where" "unknown key '$key' (known: ${V42_CFG_KEYS//$'\n'/ })"
    return 2
    ;;
  esac
  V42_CFG["$V42_CFG_CURRENT.$key"]="$value"
}

_v42_cfg_resolve() {
  local path="$2"
  case "$path" in
  /*) ;;
  *) path="$1/$path" ;;
  esac
  (cd "$path" 2>/dev/null && pwd) || printf '%s' "$path"
}

# A raised floor is honoured; a lower or non-numeric one is dropped with a note.
_v42_cfg_override() {
  local target="$1" upper var value
  upper="${target^^}"
  upper="${upper//-/_}"
  var="VAULT42_${upper}_ROOT"
  [ -z "${!var:-}" ] || V42_CFG["$target.root"]="$(cd "${!var}" 2>/dev/null && pwd || printf '%s' "${!var}")"
  var="VAULT42_${upper}_STAGE_DIR"
  [ -z "${!var:-}" ] || V42_CFG["$target.stage_dir"]="${!var}"
  var="VAULT42_${upper}_PRIVATE_ADD"
  [ -z "${!var:-}" ] || V42_CFG["$target.private_add"]="$(v42_cfg "$target" private_add) ${!var}"
  var="VAULT42_${upper}_MIN_FREE_MB"
  value="${!var:-}"
  [ -n "$value" ] || return 0
  if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt "$(v42_cfg "$target" min_free_mb)" ]; then
    V42_CFG["$target.min_free_mb"]="$value"
  else
    printf 'vault42: %s ignored: it may only raise min_free_mb above %s\n' "$var" "$(v42_cfg "$target" min_free_mb)" >&2
  fi
}

_v42_cfg_in() {
  local item="$1" word
  shift
  for word; do [ "$word" != "$item" ] || return 0; done
  return 1
}

# Value rules per key. Everything that reaches an argv or a path is held to a safe alphabet.
_v42_cfg_validate_target() {
  local t="$1" k kinds word
  for k in org project env; do
    [[ "$(v42_cfg "$t" "$k")" =~ ^[A-Za-z0-9._-]+$ ]] || {
      _v42_cfg_err "[$t]" "'$k' is required and may hold only letters, digits . _ -"
      return 2
    }
  done
  _v42_cfg_in "$(v42_cfg "$t" mode)" team personal || {
    _v42_cfg_err "[$t]" "mode must be team or personal"
    return 2
  }
  _v42_cfg_in "$(v42_cfg "$t" personal_fallback)" yes no || {
    _v42_cfg_err "[$t]" "personal_fallback must be yes or no"
    return 2
  }
  [[ "$(v42_cfg "$t" min_free_mb)" =~ ^[0-9]+$ ]] || {
    _v42_cfg_err "[$t]" "min_free_mb must be a whole number"
    return 2
  }
  _v42_cfg_in "$(v42_cfg "$t" guard)" '' sole-holder || {
    _v42_cfg_err "[$t]" "guard must be sole-holder"
    return 2
  }
  read -ra kinds <<<"$(v42_cfg "$t" kinds)"
  [ "${#kinds[@]}" -gt 0 ] || {
    _v42_cfg_err "[$t]" "kinds is empty"
    return 2
  }
  for word in "${kinds[@]}"; do
    _v42_cfg_in "$word" env secrets volumes || {
      _v42_cfg_err "[$t]" "unknown kind '$word' (env secrets volumes)"
      return 2
    }
  done
  if _v42_cfg_in volumes "${kinds[@]}" && [ "${#kinds[@]}" -gt 1 ]; then
    _v42_cfg_err "[$t]" "a volumes target cannot mix other kinds"
    return 2
  fi
}

v42_config_load() {
  local file="$1" dir line n=0 t k
  V42_CFG=()
  V42_TARGETS=()
  V42_CFG_CURRENT=""
  [ -f "$file" ] || {
    _v42_cfg_err "$file" "no such file (use --config PATH or \$VAULT42_CONFIG)"
    return 2
  }
  dir="$(cd "$(dirname "$file")" && pwd)"
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    _v42_cfg_line "$file:$n" "$line" || return 2
  done <"$file"
  [ "${#V42_TARGETS[@]}" -gt 0 ] || {
    _v42_cfg_err "$file" "no [target] section"
    return 2
  }
  for t in "${V42_TARGETS[@]}"; do
    for k in root stage_dir stack_file; do
      [ -z "$(v42_cfg "$t" "$k")" ] || V42_CFG["$t.$k"]="$(_v42_cfg_resolve "$dir" "$(v42_cfg "$t" "$k")")"
    done
    _v42_cfg_validate_target "$t" || return 2
    _v42_cfg_override "$t"
  done
}

v42_config_show() {
  local t k
  for t in "${V42_TARGETS[@]}"; do
    printf '[%s]\n' "$t"
    for k in $V42_CFG_KEYS; do
      [ -z "$(v42_cfg "$t" "$k")" ] || printf '%s = %s\n' "$k" "$(v42_cfg "$t" "$k")"
    done
  done
}
