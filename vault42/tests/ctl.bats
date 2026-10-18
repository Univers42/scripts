#!/usr/bin/env bats
# lib/ctl.sh alone: runner choice, stdin discipline (C8), the version list (C9), the docker
# runner's shape (C10), and credentials staying out of every argv.
bats_require_minimum_version 1.5.0

load helpers/common

setup() {
  fakes_setup
  . "$BATS_TEST_DIRNAME/../lib/common.sh"
  . "$BATS_TEST_DIRNAME/../lib/creds.sh"
  . "$BATS_TEST_DIRNAME/../lib/ctl.sh"
  mkdir -p "$BATS_TEST_TMPDIR/work"
  cd "$BATS_TEST_TMPDIR/work"
}

teardown() { assert_no_stdin_violation; }

@test "runner: CTL_BIN beats PATH; no 42ctl and no image is status 1" {
  cp "$FAKE_42CTL" "$BATS_TEST_TMPDIR/mine"
  CTL_BIN="$BATS_TEST_TMPDIR/mine" v42_ctl_setup
  [ "$V42_CTL_BIN" = "$BATS_TEST_TMPDIR/mine" ]
  v42_ctl_setup
  [ "$V42_CTL_BIN" = "$BATS_TEST_TMPDIR/bin/42ctl" ]
  rm "$BATS_TEST_TMPDIR/bin/42ctl"
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run --separate-stderr v42_ctl_setup
  [ "$status" -eq 1 ]
  [[ "$stderr" == *CTL_IMAGE* ]]
}

@test "C8: a call that is handed a pipe with data still sees EOF on stdin" {
  echo 'unread data' | v42_ctl none auth me
  [ ! -e "$FAKE42/stdin-violation" ]
  echo 'unread data' | v42_ctl keystore auth whoami || true
  [ ! -e "$FAKE42/stdin-violation" ]
}

@test "C8: v42_ctl_feed hands stdin to the one command that reads it" {
  echo -n 'the value' | v42_ctl_feed keystore env secret set --env e infra/KEY
  [ "$(cat "$FAKE42/secret/infra/KEY")" = 'the value' ]
}

@test "credentials reach 42ctl as the level says and never in its argv" {
  export FT_PASSPHRASE=PLANT-pass FT_PASSWORD=PLANT-pw FT_EMAIL=PLANT-mail FT_TENANT=PLANT-tenant VAULT42_REGISTER_TOKEN=PLANT-token
  v42_ctl keystore auth whoami
  v42_ctl none auth me
  v42_ctl login auth login --password
  run grep -c PLANT "$FAKE42/argv.log"
  [ "$output" = 0 ]
  run grep -c 'argv=auth whoami pass=yes password=no email=no token=no s3=no extra=$' "$FAKE42/argv.log"
  [ "$output" = 1 ]
  run grep -c 'argv=auth me pass=no' "$FAKE42/argv.log"
  [ "$output" = 1 ]
  run grep -c 'argv=auth login --password pass=yes password=yes email=yes token=no' "$FAKE42/argv.log"
  [ "$output" = 1 ]
}

@test "C9: the version list is the two verified versions" {
  [ "$V42_CTL_VERSIONS" = "0.1.15 0.1.16" ]
  run v42_ctl_version
  [ "$output" = 0.1.16 ]
}

@test "C9: an unlisted native version refuses push and only warns on read" {
  echo 0.1.17 >"$FAKE42/version"
  run --separate-stderr v42_ctl_gate push
  [ "$status" -eq 1 ]
  [[ "$stderr" == *0.1.17* && "$stderr" == *"not in the verified list"* ]]
  run --separate-stderr v42_ctl_gate read
  [ "$status" -eq 0 ]
  [[ "$stderr" == *warning* && "$stderr" == *0.1.17* ]]
}

@test "C9: there is no flag or variable that widens the list" {
  echo 0.1.17 >"$FAKE42/version"
  VAULT42_CTL_VERSIONS="0.1.17" CTL_VERSIONS="0.1.17" run v42_ctl_gate push
  [ "$status" -eq 1 ]
}

@test "C9: a listed native version passes push" {
  run v42_ctl_gate push
  [ "$status" -eq 0 ]
}

@test "C9: docker push needs a pinned image on a listed version" {
  use_docker_runner reg.example/42ctl:latest
  run --separate-stderr v42_ctl_gate push
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not pinned"* ]]
  run --separate-stderr v42_ctl_gate read
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"not pinned"* ]]
  use_docker_runner
  run v42_ctl_gate push
  [ "$status" -eq 0 ]
  FAKE_CTL_VERSION="42ctl 0.1.17" run --separate-stderr v42_ctl_gate push
  [ "$status" -eq 1 ]
  [[ "$stderr" == *0.1.17* ]]
}

@test "C9: an image whose --version fails refuses push" {
  use_docker_runner
  FAKE_CTL_VERSION_FAIL=1 run --separate-stderr v42_ctl_gate push
  [ "$status" -eq 1 ]
  [[ "$stderr" == *unknown* ]]
}

@test "C10: the docker runner mounts the working directory at the same path and the config dir" {
  use_docker_runner
  v42_ctl none auth me
  run grep -c "^run --rm -e FT_CONFIG=/cfg/config.json -e FT_KEYSTORE=/cfg/keystore.v42 -v $CTL_CFG_DIR:/cfg -v $PWD:$PWD -w $PWD $CTL_IMAGE auth me\$" "$FAKE_DOCKER/argv.log"
  [ "$output" = 1 ]
}

@test "C10: --user 0:0 only when docker is rootless, --network host only when asked" {
  use_docker_runner
  v42_ctl none auth me
  run grep -cE -e '--user|--network' "$FAKE_DOCKER/argv.log"
  [ "$output" = 0 ]
  : >"$FAKE_DOCKER/argv.log"
  FAKE_ROOTLESS=1 VAULT42_DOCKER_NETWORK=host v42_ctl none auth me
  run grep -c -e '^run --rm --user 0:0 --network host -e FT_CONFIG' "$FAKE_DOCKER/argv.log"
  [ "$output" = 1 ]
  : >"$FAKE_DOCKER/argv.log"
  VAULT42_DOCKER_NETWORK=bridge v42_ctl none auth me
  run grep -c -e '--network' "$FAKE_DOCKER/argv.log"
  [ "$output" = 0 ]
}

@test "C10: docker gets credentials by name only, and 42ctl inside sees just the level's" {
  use_docker_runner
  export FT_PASSPHRASE=PLANT-pass FT_PASSWORD=PLANT-pw FT_EMAIL=PLANT-mail
  v42_ctl keystore auth whoami
  run grep -c PLANT "$FAKE_DOCKER/argv.log"
  [ "$output" = 0 ]
  run grep -c -e '-e FT_PASSPHRASE -v' "$FAKE_DOCKER/argv.log"
  [ "$output" = 1 ]
  run grep -c 'argv=auth whoami pass=yes password=no email=no' "$FAKE42/argv.log"
  [ "$output" = 1 ]
}
