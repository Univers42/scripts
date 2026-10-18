# shellcheck shell=bash
# targets.sh — which targets a command acts on, from the global --target and --kind flags. Sourced;
# sets no shell options; needs config.sh, kinds.sh and common.sh. The entry script fills
# V42_TARGET_FLAG and V42_KINDS (a word array) before any of these run.
#
#   v42_pick_targets     V42_SEL = the --target, or every target; status 2 on an unknown name or a root
#                        that is not a directory (before any 42ctl or docker call)
#   v42_scoped_targets   V42_SEL narrowed to the targets the selected kinds touch; status 2 when none
#   v42_single_target    V42_T = the one target a state-changing command acts on; status 2 when
#                        several remain and no --target was given

v42_pick_targets() {
  local t marker="$V42_TARGET_FLAG."
  V42_SEL=()
  if [ -z "$V42_TARGET_FLAG" ]; then
    mapfile -t V42_SEL < <(v42_targets)
  elif [ -z "${V42_CFG[$marker]+x}" ]; then
    usage_error "no target '$V42_TARGET_FLAG' in the config; targets: $(v42_targets | paste -sd' ')"
    return 2
  else
    V42_SEL=("$V42_TARGET_FLAG")
  fi
  for t in "${V42_SEL[@]}"; do
    [ -d "$(v42_cfg "$t" root)" ] || {
      usage_error "target $t: root $(v42_cfg "$t" root) does not exist; fix root in the config"
      return 2
    }
  done
}

v42_scoped_targets() {
  local t
  local -a kept=()
  v42_pick_targets || return 2
  for t in "${V42_SEL[@]}"; do
    [ "$(v42_kind_scope "$t" "${V42_KINDS[@]}")" = none ] || kept+=("$t")
  done
  V42_SEL=("${kept[@]}")
  [ "${#V42_SEL[@]}" -gt 0 ] || usage_error "no target holds the selected kinds (${V42_KINDS[*]}); see: vault42 config show"
}

v42_single_target() {
  v42_scoped_targets || return 2
  if [ "${#V42_SEL[@]}" -ne 1 ]; then
    usage_error "this command acts on one target; pick one with --target (${V42_SEL[*]})"
    return 2
  fi
  # shellcheck disable=SC2034 # read by the command modules, which shellcheck checks apart
  V42_T="${V42_SEL[0]}"
}
