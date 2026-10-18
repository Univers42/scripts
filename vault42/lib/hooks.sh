# shellcheck shell=bash
# hooks.sh — run the config's `pre_push` / `post_pull` commands. Sourced; sets no shell options;
# needs config.sh, creds.sh, scan.sh and common.sh.
#
#   v42_hook_check ROOT HOOK     status 2 (message on stderr) unless every file the hook names is safe
#   v42_hook_run ROOT HOOK LEVEL run HOOK with cwd ROOT, stdin /dev/null and LEVEL's credentials
#                                (creds.sh: `none` for pre_push, `hook` for post_pull); the hook's
#                                own status is returned. An empty HOOK is a successful no-op.
#
# A hook is split into argv on whitespace and executed. It is NEVER handed to a shell, so quoting,
# `$(…)`, `;`, `|` and `>` are literal characters of an argument, not syntax.
#
# What makes a hook file safe: it is a regular file (not a symlink) inside ROOT, tracked by git, not
# under a secrets/ directory, and not among the files the scan would upload. A hook that is none of
# those is code a vault pull or an untracked edit could have swapped, and it would run with the
# keystore passphrase.
#
# Caveat: "names a file" means a whitespace-separated token that is an existing file under ROOT. A
# script reached by an indirection the tokens do not show (`sh -c`, a wrapper that sources another
# file, a PATH lookup) is checked only up to the file named; the tracked file may itself run
# anything. The check stops a swapped file, not a malicious committed one.

_v42_hook_tokens() {
  read -ra V42_HOOK_ARGV <<<"$1"
}

# Prints the path of TOKEN relative to ROOT when TOKEN is a file; nothing otherwise.
_v42_hook_file() {
  local root="$1" token="$2" path
  case "$token" in
  /*) path="$token" ;;
  *) path="$root/$token" ;;
  esac
  [ -e "$path" ] && [ ! -d "$path" ] || return 1
  printf '%s' "$path"
}

_v42_hook_reject() {
  note "hook refused: $1 ($2)"
  return 2
}

_v42_hook_check_file() {
  local root="$1" path="$2" real_dir real rel
  [ ! -L "$path" ] || {
    _v42_hook_reject "$path" "a symlink can be repointed"
    return 2
  }
  real_dir="$(cd "$(dirname "$path")" && pwd -P)"
  real="$real_dir/$(basename "$path")"
  rel="${real#"$root"/}"
  [ "$rel" != "$real" ] || {
    _v42_hook_reject "$path" "outside $root"
    return 2
  }
  case "/$rel/" in
  */secrets/* | */.secrets/*)
    _v42_hook_reject "$rel" "it sits under a secrets directory"
    return 2
    ;;
  esac
  if vault42_scan "$root" | grep -qxF -- "$rel"; then
    _v42_hook_reject "$rel" "the scan would upload it"
    return 2
  fi
  git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 ||
    {
      _v42_hook_reject "$rel" "not tracked by git"
      return 2
    }
}

v42_hook_check() {
  local root path token
  [ -n "$2" ] || return 0
  root="$(cd "$1" && pwd -P)"
  _v42_hook_tokens "$2"
  for token in "${V42_HOOK_ARGV[@]}"; do
    path="$(_v42_hook_file "$root" "$token")" || continue
    _v42_hook_check_file "$root" "$path" || return 2
  done
}

v42_hook_run() {
  local root="$1" hook="$2" level="$3"
  [ -n "$hook" ] || return 0
  v42_hook_check "$root" "$hook" || return 2
  _v42_hook_tokens "$hook"
  (cd "$root" && v42_with_creds "$level" "${V42_HOOK_ARGV[@]}" </dev/null)
}
