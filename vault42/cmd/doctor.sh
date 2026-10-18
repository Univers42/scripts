# shellcheck shell=bash
# doctor.sh — `vault42 doctor` (alias `status`): read-only checks of the toolchain, the environment
# and the session. Defines functions only; sourced by vault42.sh.
#
# Exit code: 5 when the passphrase is missing, else 2 when the config is invalid, else 1 when any
# check FAILed, else 0. The other credentials are needed only by `login`, so unset they are SKIP
# and never fail a CI run.
#
# Caveat: the session and contract verdicts read the wording of 42ctl 0.1.16 (`auth status` exits 0
# and says "logged out" or "logged in — session and contract"; `auth me` says "not logged in" or
# HTTP 401). A 42ctl that words them differently gets the generic "auth me failed" row, never a
# false OK, because `auth me` failing is what decides. Caveat: the authority URL is the second
# column of the `authority` line of `42ctl config show`; any other shape makes the network
# explanation SKIP, never a FAIL.

V42_DOC_FAILS=0

_doc_row() {
  local status="$1" name="$2"
  shift 2
  printf '%-4s %-14s %s\n' "$status" "$name" "$*"
  [ "$status" != FAIL ] || V42_DOC_FAILS=$((V42_DOC_FAILS + 1))
}

_doc_ctl() {
  local version
  if ! v42_ctl_setup 2>/dev/null; then
    _doc_row FAIL 42ctl "not found: install it on PATH, set CTL_BIN, or set CTL_IMAGE to a pinned image"
    return 1
  fi
  version="$(v42_ctl_version)" || version=unknown
  case " $V42_CTL_VERSIONS " in
  *" $version "*) _doc_row OK 42ctl "$version via $V42_CTL_KIND" ;;
  *) _doc_row WARN 42ctl "$version is not in the verified list ($V42_CTL_VERSIONS); pull/list work, push is refused" ;;
  esac
}

_doc_config() {
  local t
  if [ "${V42_CONFIG_RC:-0}" -ne 0 ]; then
    _doc_row FAIL config "invalid or missing (see the message above)"
    return 1
  fi
  for t in "${V42_TARGETS[@]}"; do
    _doc_row OK config "target $t: $(v42_cfg "$t" org)/$(v42_cfg "$t" project)/$(v42_cfg "$t" env), kinds $(v42_cfg "$t" kinds)"
  done
}

_doc_cred() {
  local what="$1" label="$2" need="$3" name
  name="$(v42_cred_name "$what")"
  if [ -z "$name" ]; then
    _doc_row SKIP "$label" "unset; $need"
  elif [ "$name" = "$label" ]; then
    _doc_row OK "$label" "set"
  else
    _doc_row OK "$label" "set (via the alias $name)"
  fi
}

_doc_creds() {
  local rc=0
  if [ -z "$(v42_cred passphrase)" ]; then
    _doc_row FAIL FT_PASSPHRASE "unset; export it to unlock the keystore"
    note "FT_PASSPHRASE is not set: export it to unlock the keystore (VAULT42_PASSPHRASE is accepted as an alias)"
    rc=5
  else
    _doc_cred passphrase FT_PASSPHRASE ""
  fi
  _doc_cred password FT_PASSWORD "needed only by \`vault42 login\`"
  _doc_cred email FT_EMAIL "needed only by \`vault42 login\`"
  _doc_cred tenant FT_TENANT "needed only by \`vault42 login\`"
  return "$rc"
}

# A missing passphrase still leaves the session checkable: the operator gets every
# diagnosis in one run instead of fixing them one exit at a time.
_doc_skip_keyed() {
  local t
  _doc_row SKIP keystore "needs FT_PASSPHRASE"
  _doc_session
  [ "${V42_CONFIG_RC:-0}" -ne 0 ] && return 0
  for t in "${V42_TARGETS[@]}"; do
    _doc_row SKIP "keys $t" "needs FT_PASSPHRASE"
  done
}

_doc_network() {
  local url why
  url="$(v42_ctl none config show 2>/dev/null | awk '$1 == "authority" { print ($2 == "=" ? $3 : $2); exit }')"
  if [ -z "$url" ]; then
    _doc_row SKIP network "the authority URL is not in \`42ctl config show\`"
    return 0
  fi
  why="$(v42_net_explain "$url")"
  _doc_row INFO network "$why"
}

_doc_not_logged_in() {
  _doc_row FAIL session "not logged in on this machine: run \`vault42 login\` (needs FT_EMAIL, FT_PASSWORD, FT_TENANT)"
}

# `auth status` exits 0 even when logged out, so its words decide; `auth me` then proves the
# server still accepts the session, and its error says why not.
_doc_session() {
  local status me
  if ! status="$(v42_ctl none auth status 2>&1)"; then
    _doc_row FAIL session "42ctl auth status failed: ${status%%$'\n'*}"
    return 1
  fi
  case "$status" in *"logged out"* | *"not logged in"*)
    _doc_not_logged_in
    return 1
    ;;
  esac
  if ! me="$(v42_ctl none auth me 2>&1)"; then
    case "$me" in
    *"not logged in"*) _doc_not_logged_in ;;
    *401* | *expired*) _doc_row FAIL session "the session expired: run \`vault42 login\`" ;;
    *)
      me="${me%%$'\n'*}"
      _doc_row FAIL session "42ctl auth me failed: ${me:0:160}"
      _doc_network
      ;;
    esac
    return 1
  fi
  _doc_row OK session "the server accepts the session"
  case "$status" in
  *contract*) _doc_row OK contract "the session carries a contract" ;;
  *) _doc_row WARN contract "no contract on this session: \`vault42 login\` takes one with FT_TENANT" ;;
  esac
}

_doc_keystore() {
  if v42_ctl keystore auth whoami >/dev/null 2>&1; then
    _doc_row OK keystore "unlocked"
  else
    _doc_row FAIL keystore "could not unlock: check FT_PASSPHRASE"
  fi
}

_doc_keys() {
  local t rows me state
  for t in "${V42_TARGETS[@]}"; do
    if ! rows="$(v42_keys_rows "$t" 2>/dev/null)" || ! me="$(v42_my_account 2>/dev/null)"; then
      _doc_row WARN "keys $t" "could not read the key holders"
      continue
    fi
    state="$(v42_my_state "$rows" "$me")"
    if [ "$state" = active ]; then _doc_row OK "keys $t" "your key is active"; else _doc_row FAIL "keys $t" "your key is $state"; fi
  done
}

cmd_doctor() {
  local rc=0
  V42_DOC_FAILS=0
  _doc_ctl
  _doc_config || rc=2
  _doc_creds || { [ "$?" -ne 5 ] || rc=5; }
  if [ "$rc" -eq 5 ]; then
    _doc_skip_keyed
  else
    _doc_keystore
    _doc_session
    [ "$V42_CONFIG_RC" -ne 0 ] || _doc_keys
  fi
  [ "$rc" -eq 0 ] || return "$rc"
  [ "$V42_DOC_FAILS" -eq 0 ] || return 1
}
