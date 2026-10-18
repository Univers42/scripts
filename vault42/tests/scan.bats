#!/usr/bin/env bats
# vault42/lib/scan.sh — vault42_scan must list exactly what 42ctl 4ee32f6 uploads:
# *.env* / *.secrets by file name (or the .42ctl/project.json patterns), every file under a
# secrets/ or .secrets/ dir, never *.bak* / *.stale, symlinks, .42ctl, or the 14 skip dirs —
# except a repository (a dir holding .git) directly inside a skip dir, walked with the secrets
# flag reset. vault42_unscanned lists git-ignored files, submodules included, that the scan
# misses. Synthetic trees only; contents are never read.
#

bats_require_minimum_version 1.5.0

setup() {
  . "$BATS_TEST_DIRNAME/../lib/scan.sh"
  R="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$R"
}

# mk PATH... — create empty files, parents included.
mk() {
  local p
  for p in "$@"; do
    mkdir -p "$(dirname "$R/$p")"
    : >"$R/$p"
  done
}

scan() { vault42_scan "$R"; }

@test "takes *.env* names at any depth" {
  mk .env .env.local config.env.example a/b/c/app.env nope.txt a/readme
  run scan
  [ "$status" -eq 0 ]
  [ "$output" = $'.env\n.env.local\na/b/c/app.env\nconfig.env.example' ]
}

@test "takes *.secrets" {
  mk db.secrets x/y.secrets secrets.txt
  run scan
  [ "$output" = $'db.secrets\nx/y.secrets' ]
}

@test "secrets/ takes every file at any depth" {
  mk secrets/pw.txt secrets/tls/server.key other/pw.txt
  run scan
  [ "$output" = $'secrets/pw.txt\nsecrets/tls/server.key' ]
}

@test ".secrets/ takes every file" {
  mk .secrets/token a/.secrets/deep/x other/token
  run scan
  [ "$output" = $'.secrets/token\na/.secrets/deep/x' ]
}

@test ".bak and .stale are skipped, also inside secrets" {
  mk secrets/x.bak-2026 secrets/ok.txt secrets/old.stale .env.local.bak-20261015 .env.stale .env
  run scan
  [ "$output" = $'.env\nsecrets/ok.txt' ]
}

@test "symlinked file and symlinked dir are not taken" {
  mk real.env real/.env
  ln -s real.env "$R/link.env"
  ln -s real "$R/linkdir"
  mkdir -p "$R/secrets"
  ln -s ../real.env "$R/secrets/link"
  ln -s ../real "$R/secrets/linkdir"
  run scan
  [ "$output" = $'real.env\nreal/.env' ]
}

@test "each skip dir is not descended" {
  local d
  for d in node_modules .git target dist build vendor .cache coverage __pycache__ .next .venv .claude .vault baas.bak; do
    mk "$d/.env" "a/$d/.env" "secrets/$d/key"
  done
  mk keep.env
  run scan
  [ "$output" = "keep.env" ]
}

@test "a repository directly inside vendor/ is scanned, deeper is not" {
  mk vendor/repo/.git vendor/repo/app.env vendor/repo/secrets/k vendor/repo/a.txt
  mk vendor/plain/.env vendor/x/repo/.git vendor/x/repo/.env
  run scan
  [ "$output" = $'vendor/repo/app.env\nvendor/repo/secrets/k' ]
}

@test "a repository whose .git is a directory is pierced too" {
  mk node_modules/pkg/.git/HEAD node_modules/pkg/.env
  run scan
  [ "$output" = "node_modules/pkg/.env" ]
}

@test "a skip dir inside a pierced repository is pierced again" {
  mk vendor/repo/.git vendor/repo/node_modules/inner/.git vendor/repo/node_modules/inner/.env
  mk vendor/repo/node_modules/dead/.env
  run scan
  [ "$output" = "vendor/repo/node_modules/inner/.env" ]
}

@test "the secrets flag resets inside a pierced repository" {
  mk secrets/a.txt secrets/vendor/repo/.git secrets/vendor/repo/a.txt secrets/vendor/repo/b.env
  run scan
  [ "$output" = $'secrets/a.txt\nsecrets/vendor/repo/b.env' ]
}

@test ".42ctl is never descended" {
  mk .42ctl/x.env .env
  run scan
  [ "$output" = ".env" ]
}

@test "a ROOT named secrets takes everything" {
  R="$BATS_TEST_TMPDIR/secrets"
  mkdir -p "$R"
  mk pw.txt sub/key old.bak
  run scan
  [ "$output" = $'pw.txt\nsub/key' ]
}

@test "project.json patterns replace the defaults" {
  mk .42ctl/project.json a.conf deep/b.conf .env secrets/s.txt
  printf '{"project_id":"x","patterns":["*.conf"]}' >"$R/.42ctl/project.json"
  run scan
  [ "$output" = $'a.conf\ndeep/b.conf\nsecrets/s.txt' ]
}

@test "a path-shaped pattern is refused" {
  mk .42ctl/project.json .env
  printf '{"project_id":"x","patterns":["srcs/.env"]}' >"$R/.42ctl/project.json"
  run scan
  [ "$status" -eq 1 ]
}

@test "a * in the middle matches any run, and regex characters are literal" {
  mk .42ctl/project.json a-b.conf aXb.conf 'a.b+c' 'aqb+c'
  printf '{"project_id":"x","patterns":["a*b.conf","a.b+c"]}' >"$R/.42ctl/project.json"
  run scan
  [ "$output" = $'a-b.conf\na.b+c\naXb.conf' ]
}

@test "output is relative and LC_ALL=C sorted" {
  mk b/.env B/.env a/.env .env
  run scan
  [ "$output" = $'.env\nB/.env\na/.env\nb/.env' ]
}

@test "a missing ROOT fails" {
  run vault42_scan "$BATS_TEST_TMPDIR/absent"
  [ "$status" -eq 1 ]
}

# --- vault42_unscanned -------------------------------------------------------------------

git_fixture() {
  git -C "$R" init -q
  printf '*.local*\ncerts/\nnode_modules/\nsecrets/\n' >"$R/.gitignore"
  mk .env.local .env.local.bak-1 certs/ca-key.pem secrets/dump.gz node_modules/x/.env keep.txt
  mk dist/ignored-by-name.js
  printf 'dist/\n' >>"$R/.gitignore"
}

@test "unscanned lists ignored files the scan misses" {
  git_fixture
  run vault42_unscanned "$R"
  [ "$status" -eq 0 ]
  [ "$output" = $'.env.local.bak-1\ncerts/ca-key.pem' ]
}

@test "unscanned does not list scanned, build-output or tracked files" {
  git_fixture
  run vault42_unscanned "$R"
  run ! grep -Fx -e '.env.local' -e 'secrets/dump.gz' -e 'node_modules/x/.env' -e 'dist/ignored-by-name.js' -e 'keep.txt' <<<"$output"
}

@test "unscanned skips ignored symlinks" {
  git_fixture
  ln -s keep.txt "$R/certs-link.local"
  run vault42_unscanned "$R"
  run ! grep -F 'certs-link.local' <<<"$output"
}

@test "unscanned prints nothing outside a git repo" {
  mk .env.local.bak-1
  run vault42_unscanned "$R"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unscanned reaches checked-out submodules with relative paths" {
  local sub="$BATS_TEST_TMPDIR/sub"
  git init -q "$sub"
  printf 'private/\n' >"$sub/.gitignore"
  : >"$sub/f"
  git -C "$sub" add . && git -C "$sub" -c user.name=t -c user.email=t@t commit -qm i
  git -C "$R" init -q
  git -C "$R" -c protocol.file.allow=always submodule add -q "$sub" apps/sub
  mkdir -p "$R/apps/sub/private"
  : >"$R/apps/sub/private/key.pem"
  : >"$R/apps/sub/.env"
  printf 'private/\n.env\n' >>"$R/.git/modules/apps/sub/info/exclude"
  run vault42_unscanned "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "apps/sub/private/key.pem" ]
}

@test "unscanned drops an ignored pkg/ build directory but keeps a pkg-prefixed file" {
  git -C "$R" init -q
  printf 'engine/pkg/\npkgconf.txt\n' >"$R/.gitignore"
  mk engine/pkg/x.wasm pkgconf.txt
  run vault42_unscanned "$R"
  [ "$status" -eq 0 ]
  [ "$output" = "pkgconf.txt" ]
}

@test "C15: the scan over this checkout returns nothing under vault42/" {
  run vault42_scan "$BATS_TEST_DIRNAME/../.."
  [ "$status" -eq 0 ]
  run grep -c '^vault42/' <<<"$output"
  [ "$output" = 0 ]
}
