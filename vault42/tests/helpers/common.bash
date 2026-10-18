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
