# shellcheck shell=bash
# Shared bats setup: a clean credential environment, the fakes on PATH, and a git repo to act on.
# Every test starts with ALL credential variables unset, so a pass never leans on the host's.

V42_ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
export V42_ROOT_DIR

fakes_setup() {
  local n
  for n in FT_PASSPHRASE FT_PASSWORD FT_EMAIL FT_TENANT VAULT42_REGISTER_TOKEN VAULT42_PASSPHRASE \
    FT_LOGIN_EMAIL FT_REGISTER_TOKEN FT_S3_KEY FT_S3_SECRET VAULT42_CONFIG GROBASE_ENV; do
    unset "$n"
  done
  export FAKE42="$BATS_TEST_TMPDIR/fake42" FAKE_DOCKER="$BATS_TEST_TMPDIR/fakedocker"
  export FAKE_SCAN_LIB="$V42_ROOT_DIR/lib/scan.sh" FAKE_42CTL="$BATS_TEST_TMPDIR/ctl/42ctl"
  mkdir -p "$BATS_TEST_TMPDIR/ctl" "$FAKE42" "$FAKE_DOCKER/volumes" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/out"
  : >"$FAKE_DOCKER/ps"
  : >"$FAKE_DOCKER/argv.log"
  cp "$BATS_TEST_DIRNAME/helpers/fake-42ctl" "$FAKE_42CTL"
  cp "$FAKE_42CTL" "$BATS_TEST_TMPDIR/bin/42ctl"
  cp "$BATS_TEST_DIRNAME/helpers/fake-docker" "$BATS_TEST_TMPDIR/bin/docker"
  cp "$BATS_TEST_DIRNAME/helpers/fake-curl" "$BATS_TEST_TMPDIR/bin/curl"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# A fake 42ctl that read a terminal or non-empty stdin leaves this file behind (C8).
assert_no_stdin_violation() {
  [ ! -e "$FAKE42/stdin-violation" ] || {
    cat "$FAKE42/stdin-violation" >&2
    return 1
  }
}

# The docker runner is the only way to 42ctl: the native binary leaves PATH, the image is set.
use_docker_runner() {
  rm -f "$BATS_TEST_TMPDIR/bin/42ctl"
  export CTL_IMAGE="${1:-reg.example/42ctl@sha256:$(printf 'a%.0s' $(seq 64))}"
  export CTL_CFG_DIR="$BATS_TEST_TMPDIR/ctlcfg"
  mkdir -p "$CTL_CFG_DIR"
}

# load_lib NAME… — source lib/NAME.sh for each.
load_lib() {
  local n
  # shellcheck disable=SC1090 # the lib list is the caller's; each file is checked on its own
  for n in "$@"; do . "$V42_ROOT_DIR/lib/$n.sh"; done
}

# make_repo [DIR] — a git repo at DIR (default $BATS_TEST_TMPDIR/repo), echoed.
make_repo() {
  local dir="${1:-$BATS_TEST_TMPDIR/repo}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  printf '%s' "$dir"
}

# write_conf ROOT [EXTRA LINE…] — a one-target config named `t` for env e, root ROOT, at $CONF.
write_conf() {
  local root="$1"
  shift
  CONF="$BATS_TEST_TMPDIR/vault42.conf"
  printf '%s\n' '[t]' 'org = o' 'project = p' 'env = e' "root = $root" "$@" >"$CONF"
  export CONF
}

# commit_all REPO — track everything so hooks pass the "tracked file" check.
commit_all() {
  git -C "$1" add -A
  git -C "$1" -c user.email=t@example.test -c user.name=t commit -qm fixture
}

# proj_setup — a repo with a.env, b.env and secrets/k.env, a one-target config, a signed-in fake.
# Sets R, CONF and V42; the vault starts without a tree.
proj_setup() {
  R="$(make_repo)"
  printf 'AAAA' >"$R/a.env"
  printf 'BBBB' >"$R/b.env"
  mkdir -p "$R/secrets" "$R/scripts"
  printf 'KKKK' >"$R/secrets/k.env"
  printf 'secrets/stage.tgz\ncache.dump\n' >"$R/.gitignore"
  write_conf "$R" "private = secrets/*.env"
  export VAULT42_CONFIG="$CONF" FT_PASSPHRASE=pass-planted-1111
  printf '7704efb0-5a6a-4117-9cdd-a9265a8fc350 active\nother active\n' >"$FAKE42/keys.e"
  export V42="$V42_ROOT_DIR/vault42.sh"
}

# add_conf LINE… — append keys to the one target of $CONF.
add_conf() { printf '%s\n' "$@" >>"$CONF"; }

# add_hook NAME BODY — a tracked, executable script under scripts/.
add_hook() {
  printf '#!/bin/sh\n%s\n' "$2" >"$R/scripts/$1"
  chmod +x "$R/scripts/$1"
  commit_all "$R"
}
