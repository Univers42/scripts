# shellcheck shell=bash
# state.sh — where the tool keeps its own files, and the one cleanup trap that removes what it
# creates. Sourced; sets no shell options.
#
#   v42_common_dir ROOT   absolute git common dir of ROOT; status 1 outside a git checkout.
#   v42_state_dir ROOT    <common dir>/vault42 (mode 700), else ROOT/.vault42. Locks, drill markers
#                         and capture state live here and nowhere else.
#   v42_mktmp ROOT        sets V42_TMP to a fresh mode-700 directory under <common dir>/vault42-tmp
#                         (never /tmp: it holds restored secrets), removed on EXIT INT TERM HUP.
#   v42_on_exit FUNCTION  run FUNCTION (no arguments) at exit, last registered first.
#
# The git common dir is shared by every linked worktree and a submodule keeps its own under the
# superproject's .git/modules, so each checkout gets one state dir however it was created.
#
# Caveat: outside git the state dir is ROOT/.vault42, which two worktrees cannot share, so the
# lock there only excludes runs that use the same directory. SIGKILL skips the trap and leaves
# a vault42-tmp child behind (mode 700, inside .git, never scanned).

V42_CLEANUP_FNS=()
V42_TMP_DIRS=()
V42_TMP=

v42_common_dir() {
  local root="$1" common
  common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$common" in
    /*) ;;
    *) common="$root/$common" ;;
  esac
  (cd "$common" && pwd)
}

v42_state_dir() {
  local root="$1" base dir
  if base="$(v42_common_dir "$root")"; then dir="$base/vault42"; else dir="$root/.vault42"; fi
  (umask 077 && mkdir -p "$dir") || return 1
  printf '%s\n' "$dir"
}

_v42_run_cleanups() {
  local i
  for ((i = ${#V42_CLEANUP_FNS[@]} - 1; i >= 0; i--)); do
    "${V42_CLEANUP_FNS[$i]}" || true
  done
}

_v42_exit_with() {
  local status="$1"
  exit "$status"
}

v42_on_exit() {
  V42_CLEANUP_FNS+=("$1")
  trap _v42_run_cleanups EXIT
  trap '_v42_exit_with 130' INT
  trap '_v42_exit_with 143' TERM
  trap '_v42_exit_with 129' HUP
}

_v42_rm_tmp_dirs() {
  local dir
  for dir in "${V42_TMP_DIRS[@]}"; do rm -rf -- "$dir"; done
  V42_TMP_DIRS=()
}

v42_mktmp() {
  local root="$1" base
  if base="$(v42_common_dir "$root")"; then base="$base/vault42-tmp"; else base="$root/.vault42-tmp"; fi
  (umask 077 && mkdir -p "$base") && chmod 700 "$base" || return 1
  V42_TMP="$(mktemp -d "$base/run.XXXXXX")" || return 1
  chmod 700 "$V42_TMP"
  V42_TMP_DIRS+=("$V42_TMP")
  [ "${#V42_TMP_DIRS[@]}" -gt 1 ] || v42_on_exit _v42_rm_tmp_dirs
}
