#!/usr/bin/env bats
# lib/seedsums.sh alone: SHA256SUMS lines for the archives next to it.
bats_require_minimum_version 1.5.0

setup() {
  . "$BATS_TEST_DIRNAME/../lib/seedsums.sh"
}

sums_dir() {
  D="$BATS_TEST_TMPDIR/seed"
  mkdir -p "$D"
  echo a >"$D/a"
  echo m >"$D/m"
  echo z >"$D/z"
}

@test "seed_sums_put creates SHA256SUMS in mode 600 and sha256sum -c passes" {
  sums_dir
  seed_sums_put "$D" z a
  [ "$(stat -c %a "$D/SHA256SUMS")" = 600 ]
  [ "$(cut -d' ' -f3 "$D/SHA256SUMS" | tr '\n' ' ')" = "a z " ]
  (cd "$D" && sha256sum -c SHA256SUMS)
}

@test "seed_sums_put adds, replaces, keeps other lines byte-identical and sorted" {
  sums_dir
  printf 'junk  b-old\n' >"$D/b-old"
  seed_sums_put "$D" a m z b-old
  cp "$D/SHA256SUMS" "$BATS_TEST_TMPDIR/before"
  echo changed >"$D/m"
  echo n >"$D/new"
  seed_sums_put "$D" new m
  (cd "$D" && sha256sum -c SHA256SUMS)
  [ "$(cut -d' ' -f3 "$D/SHA256SUMS" | tr '\n' ' ')" = "a b-old m new z " ]
  [ "$(grep -v ' m$' "$BATS_TEST_TMPDIR/before")" = "$(grep -v -e ' m$' -e ' new$' "$D/SHA256SUMS")" ]
  [ "$(stat -c %a "$D/SHA256SUMS")" = 600 ]
}

@test "seed_sums_put drops existing SHA256SUMS* lines and keeps the rest byte-for-byte" {
  sums_dir
  printf '%s  %s\n' "$(sha256sum <"$D/a" | cut -d' ' -f1)" a >"$D/SHA256SUMS"
  printf '%s  %s\n' deadbeef SHA256SUMS.new >>"$D/SHA256SUMS"
  printf '%s  %s\n' "$(sha256sum <"$D/z" | cut -d' ' -f1)" z >>"$D/SHA256SUMS"
  seed_sums_put "$D" m
  [ "$(cut -d' ' -f3 "$D/SHA256SUMS" | tr '\n' ' ')" = "a m z " ]
  [ "$(grep -c SHA256SUMS "$D/SHA256SUMS")" -eq 0 ]
  [ "$(grep ' z$' "$D/SHA256SUMS")" = "$(sha256sum <"$D/z" | cut -d' ' -f1)  z" ]
}

@test "seed_sums_put refuses names 42ctl never uploads and leaves SHA256SUMS identical" {
  sums_dir
  seed_sums_put "$D" a
  cp "$D/SHA256SUMS" "$BATS_TEST_TMPDIR/before"
  local n
  for n in SHA256SUMS SHA256SUMS.new a.bak_b x.stale .hidden; do
    [ "$n" = SHA256SUMS ] || echo x >"$D/$n"
    run --separate-stderr seed_sums_put "$D" m "$n"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"$n"* ]]
    cmp "$D/SHA256SUMS" "$BATS_TEST_TMPDIR/before"
  done
}

@test "seed_sums_put refuses a missing NAME and leaves SHA256SUMS untouched" {
  sums_dir
  seed_sums_put "$D" a
  cp "$D/SHA256SUMS" "$BATS_TEST_TMPDIR/before"
  run seed_sums_put "$D" m ghost
  [ "$status" -eq 1 ]
  cmp "$D/SHA256SUMS" "$BATS_TEST_TMPDIR/before"
  [ -z "$(ls -A "$D" | grep -e '^\.SHA')" ]
}
