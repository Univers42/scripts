# shellcheck shell=bash
# ctl.sh — run 42ctl: the native binary, else a pinned docker image. Sourced; sets no shell options;
# needs creds.sh and common.sh.
#
#   v42_ctl_setup            pick the runner (CTL_BIN, else 42ctl on PATH, else docker + CTL_IMAGE);
#                            sets V42_CTL_KIND (native|docker), V42_CTL_BIN, V42_CTL_IMAGE; status 1
#                            with a message when there is none.
#   v42_ctl LEVEL ARGS…      run 42ctl in the current directory with LEVEL's credentials (creds.sh)
#                            and stdin from /dev/null, so nothing can ever prompt or hang on input.
#   v42_ctl_feed LEVEL ARGS… the same, but stdin is this shell's: only `env secret set` reads it.
#   v42_ctl_version          the X.Y.Z the runner reports
#   v42_ctl_gate MODE        push: status 1 unless the version is listed (and a docker image is
#                            pinned); read: the same findings as warnings, status 0.
#
# The version list is a constant here and not a config key: it is what the scan mirror (scan.sh)
# was checked against, so a repository must not be able to widen it.
#
# Docker runs mount the working directory at the same path and make it the workdir, because
# `env pull` restores into the current directory; the 42ctl config directory is mounted at /cfg.
# Credentials are forwarded by NAME (`-e FT_PASSPHRASE`), so no value is ever in docker's argv.
#
# Caveat: `docker info` decides "rootless" by the word in SecurityOptions; a runtime that does not
# report it is treated as rootful and gets no `--user 0:0`. Caveat: the image digest is checked
# for shape, not for provenance; pinning proves the bytes are the ones named, not that they are good.

V42_CTL_VERSIONS="0.1.15 0.1.16"
V42_CTL_KIND=""
V42_CTL_BIN=""
V42_CTL_IMAGE=""

v42_ctl_setup() {
  V42_CTL_KIND="" V42_CTL_BIN="" V42_CTL_IMAGE=""
  if [ -n "${CTL_BIN:-}" ] && [ -x "$CTL_BIN" ]; then
    V42_CTL_KIND=native V42_CTL_BIN="$CTL_BIN"
  elif V42_CTL_BIN="$(command -v 42ctl)"; then
    V42_CTL_KIND=native
  elif [ -n "${CTL_IMAGE:-}" ] && command -v docker >/dev/null; then
    V42_CTL_KIND=docker V42_CTL_IMAGE="$CTL_IMAGE"
  else
    V42_CTL_BIN=""
    note "42ctl not found: install it on PATH, set CTL_BIN to it, or set CTL_IMAGE to a pinned image (name@sha256:<64 hex>)"
    return 1
  fi
}

_v42_is_rootless() {
  docker info --format '{{.SecurityOptions}}' 2>/dev/null </dev/null | grep -q rootless
}

# Runs inside v42_with_creds' subshell, so it sees exactly the level's variables.
_v42_ctl_docker() {
  local root="$PWD" cfg="${CTL_CFG_DIR:-$HOME/.config/42ctl}" name
  local -a argv=(run --rm)
  ! _v42_is_rootless || argv+=(--user 0:0)
  [ "${VAULT42_DOCKER_NETWORK:-}" != host ] || argv+=(--network host)
  argv+=(-e FT_CONFIG=/cfg/config.json -e FT_KEYSTORE=/cfg/keystore.v42)
  for name in FT_PASSPHRASE FT_PASSWORD FT_LOGIN_EMAIL FT_REGISTER_TOKEN FT_S3_KEY FT_S3_SECRET; do
    [ -z "${!name:-}" ] || argv+=(-e "$name")
  done
  argv+=(-v "$cfg:/cfg" -v "$root:$root" -w "$root" "$V42_CTL_IMAGE")
  docker "${argv[@]}" "$@"
}

_v42_ctl_run() {
  local level="$1" stdin="$2"
  shift 2
  [ -n "$V42_CTL_KIND" ] || v42_ctl_setup || return 1
  if [ "$V42_CTL_KIND" = native ]; then
    v42_with_creds "$level" "$V42_CTL_BIN" "$@" <"$stdin"
  else
    v42_with_creds "$level" _v42_ctl_docker "$@" <"$stdin"
  fi
}

v42_ctl() {
  local level="$1"
  shift
  _v42_ctl_run "$level" /dev/null "$@"
}

v42_ctl_feed() {
  local level="$1"
  shift
  _v42_ctl_run "$level" /dev/stdin "$@"
}

v42_ctl_version() {
  local out
  out="$(v42_ctl none --version 2>/dev/null)" || return 1
  [[ "$out" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

_v42_ctl_finding() {
  local version
  if ! version="$(v42_ctl_version)"; then
    printf '42ctl --version failed, so its version is unknown'
    return 0
  fi
  case " $V42_CTL_VERSIONS " in
    *" $version "*) ;;
    *) printf '42ctl %s is not in the verified list (%s); the scan mirror may differ' "$version" "$V42_CTL_VERSIONS" ;;
  esac
  [ "$V42_CTL_KIND" = native ] && return 0
  [[ "$V42_CTL_IMAGE" =~ ^[^@[:space:]]+@sha256:[0-9a-f]{64}$ ]] ||
    printf '%sCTL_IMAGE is not pinned as name@sha256:<64 hex>' "${version:+; }"
}

v42_ctl_gate() {
  local finding
  [ -n "$V42_CTL_KIND" ] || v42_ctl_setup || return 1
  finding="$(_v42_ctl_finding)"
  [ -n "$finding" ] || return 0
  if [ "$1" = push ]; then
    note "refusing to push: $finding"
    return 1
  fi
  note "warning: $finding"
}
