#!/usr/bin/env bats
# `vault42 doctor` end to end against the fakes: C7 (missing passphrase), C8 (CI shape), C9 (version
# warning), C16 (curl explains, 42ctl decides) and the credential-leak check.
bats_require_minimum_version 1.5.0

load helpers/common

V42="$BATS_TEST_DIRNAME/../vault42.sh"

setup() {
  fakes_setup
  R="$(make_repo)"
  write_conf "$R"
  printf '4 a.env\n' >"$FAKE42/files.e"
  printf "7704efb0-5a6a-4117-9cdd-a9265a8fc350 active\n" >"$FAKE42/keys.e"
  export VAULT42_CONFIG="$CONF"
  export FT_PASSPHRASE=pass-planted-1111
}

teardown() { assert_no_stdin_violation; }

@test "C8: the CI shape (passphrase only) exits 0 and marks the login credentials SKIP" {
  run "$V42" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP FT_PASSWORD"*"needed only by \`vault42 login\`"* ]]
  [[ "$output" == *"SKIP FT_EMAIL"* ]]
  [[ "$output" == *"SKIP FT_TENANT"* ]]
}

@test "C7: no passphrase exits 5 and stderr names FT_PASSPHRASE" {
  unset FT_PASSPHRASE
  run --separate-stderr "$V42" doctor
  [ "$status" -eq 5 ]
  [[ "$stderr" == *FT_PASSPHRASE* ]]
}

@test "doctor: without a passphrase it still checks the session and skips only what needs the key" {
  unset FT_PASSPHRASE
  run "$V42" doctor
  [ "$status" -eq 5 ]
  [[ "$output" == *"SKIP FT_PASSWORD"* ]]
  [[ "$output" == *"SKIP keystore"*"needs FT_PASSPHRASE"* ]]
  [[ "$output" == *"OK   session"* ]]
  [[ "$output" == *"SKIP keys t"*"needs FT_PASSPHRASE"* ]]
}

@test "doctor: status is an alias" {
  run "$V42" status
  [ "$status" -eq 0 ]
}

@test "doctor: an alias is used only when the canonical name is unset, and says so" {
  unset FT_PASSPHRASE
  export VAULT42_PASSPHRASE=alias-planted-2222
  run "$V42" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"FT_PASSPHRASE"*"via the alias VAULT42_PASSPHRASE"* ]]
}

@test "doctor: an invalid config exits 2" {
  printf '[t]\nbogus = 1\n' >"$CONF"
  run "$V42" doctor
  [ "$status" -eq 2 ]
}

@test "doctor: a missing passphrase wins over an invalid config (5 before 2)" {
  unset FT_PASSPHRASE
  printf '[t]\nbogus = 1\n' >"$CONF"
  run "$V42" doctor
  [ "$status" -eq 5 ]
}

@test "C9: an unlisted 42ctl version only warns in doctor" {
  echo 0.1.17 >"$FAKE42/version"
  run "$V42" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN 42ctl"*"0.1.17"* ]]
}

@test "doctor: a locked keystore fails" {
  touch "$FAKE42/locked"
  run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL keystore"* ]]
}

@test "doctor: a key that is not active fails" {
  printf "7704efb0-5a6a-4117-9cdd-a9265a8fc350 pending\n" >"$FAKE42/keys.e"
  run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL keys t"*"pending"* ]]
}

@test "C16: curl reaches the authority but 42ctl auth me fails, so doctor FAILs" {
  touch "$FAKE42/net-down"
  FAKE_CURL_MODE=http:200 run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL session"* ]]
  [[ "$output" == *"the authority answered HTTP 200"* ]]
}

@test "C16: curl failures are explained, never decisive" {
  touch "$FAKE42/net-down"
  local mode text
  for pair in "dns:DNS cannot resolve" "refused:refused the connection" "tls:TLS handshake" "timeout:did not answer within 8 seconds" "http:503:answered HTTP 503"; do
    mode="${pair%%:*}"
    text="${pair#*:}"
    [ "$mode" != http ] || {
      mode=http:503
      text="answered HTTP 503"
    }
    FAKE_CURL_MODE="$mode" run "$V42" doctor
    [ "$status" -eq 1 ]
    [[ "$output" == *"$text"* ]]
  done
}

@test "doctor: a logged-out machine (auth status exits 0) says so and names the fix" {
  touch "$FAKE42/nologin"
  run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL session"*"not logged in on this machine"*"vault42 login"* ]]
  run grep -c "OK   session" <<<"$output"
  [ "$output" = 0 ]
}

@test "doctor: an expired session (401) says expired, without blaming the network" {
  echo dead >"$FAKE42/session"
  FAKE_CURL_LOG="$BATS_TEST_TMPDIR/curl.log" run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL session"*"the session expired"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "doctor: a session without a contract warns" {
  touch "$FAKE42/nocontract"
  run "$V42" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN contract"* ]]
}

@test "doctor: the authority URL is read from the 0.1.16 column format" {
  touch "$FAKE42/net-down"
  FAKE_CURL_LOG="$BATS_TEST_TMPDIR/curl.log" FAKE_CURL_MODE=http:200 run "$V42" doctor
  run grep -c "authority.example.test" "$BATS_TEST_TMPDIR/curl.log"
  [ "$output" != 0 ]
}

@test "C16: a healthy session never runs curl" {
  FAKE_CURL_LOG="$BATS_TEST_TMPDIR/curl.log" run "$V42" doctor
  [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "leak: no credential value reaches doctor's stdout or stderr" {
  export FT_PASSWORD=pw-planted-3333 FT_EMAIL=em-planted-4444@example.test FT_TENANT=tn-planted-5555
  run --separate-stderr "$V42" doctor
  printf '%s\n%s\n' "$output" "$stderr" >"$BATS_TEST_TMPDIR/captured"
  local v
  for v in pass-planted-1111 pw-planted-3333 em-planted-4444 tn-planted-5555; do
    run grep -c "$v" "$BATS_TEST_TMPDIR/captured"
    [ "$output" = 0 ]
  done
  run grep -c "$FT_PASSPHRASE\|pw-planted" "$FAKE42/argv.log"
  [ "$output" = 0 ]
}

@test "doctor: every 42ctl call it makes had its stdin at EOF" {
  run "$V42" doctor
  assert_no_stdin_violation
}

# Two targets: t (env e, key active) and u (env f, root $R2). `keys.f` is what u's key rows say.
two_targets() {
  R2="$(make_repo "$BATS_TEST_TMPDIR/repo2")"
  printf '\n[u]\norg = o2\nproject = p2\nenv = f\nroot = %s\n' "$R2" >>"$CONF"
  printf "7704efb0-5a6a-4117-9cdd-a9265a8fc350 pending-provision\nbob pending-provision\n" >"$FAKE42/keys.f"
}

@test "doctor --target: only the selected target's keys are checked, so a broken other one does not fail" {
  two_targets
  run "$V42" --target t doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK   keys t"* ]]
  [[ "$output" != *"keys u"* ]]
  [[ "$output" == *"config         target u: o2/p2/f"* ]]
}

@test "doctor: without --target every target's keys are checked" {
  two_targets
  run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"OK   keys t"* ]]
  [[ "$output" == *"FAIL keys u"* ]]
}

@test "doctor --target: the passphrase-less run skips only the selected target" {
  two_targets
  unset FT_PASSPHRASE
  run "$V42" --target t doctor
  [ "$status" -eq 5 ]
  [[ "$output" == *"SKIP keys t"* ]]
  [[ "$output" != *"SKIP keys u"* ]]
}

@test "doctor --target: an unknown target is a usage error naming the targets" {
  two_targets
  run --separate-stderr "$V42" --target nope doctor
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no target 'nope' in the config; targets: t u"* ]]
}

@test "doctor: a target whose root is missing is a WARN row, not a failure" {
  rm -rf "$R"
  run "$V42" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN config"*"target t: o/p/e, kinds"*"root $R does not exist (create it, or fix root)"* ]]
  [[ "$output" == *"OK   keys t"* ]]
}

@test "doctor: pending-provision with active holders names the sync command to ask for" {
  printf "7704efb0-5a6a-4117-9cdd-a9265a8fc350 pending-provision\nbob active\ncarol active\n" >"$FAKE42/keys.e"
  run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL keys t"*"your key is pending-provision: one of the 2 active holders runs 42ctl env keys sync --org o --project p --env e"* ]]
}

@test "doctor: pending-provision with no active holder says nobody can provision you" {
  printf "7704efb0-5a6a-4117-9cdd-a9265a8fc350 pending-provision\nbob pending-provision\n" >"$FAKE42/keys.e"
  run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"your key is pending-provision and no member holds the o/p/e key (2 members, none active): env keys sync needs an active holder, so nobody can provision you; ask an org admin"* ]]
}

@test "doctor: pending-enrollment names keys enroll" {
  printf "7704efb0-5a6a-4117-9cdd-a9265a8fc350 pending-enrollment\n" >"$FAKE42/keys.e"
  run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"your key is pending-enrollment: publish your public keys with 42ctl keys enroll --org o, then an active holder runs env keys sync"* ]]
}

@test "doctor: a caller who is not a member is told to ask an org admin" {
  printf "bob active\n" >"$FAKE42/keys.e"
  run "$V42" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"you are not a member of o/p/e: an org admin adds you"* ]]
}
