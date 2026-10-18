# shellcheck shell=bash
# netdiag.sh — explain WHY an authority is unreachable. Sourced; sets no shell options; needs common.sh.
#
#   v42_net_explain URL   prints one sentence (DNS / refused / TLS / timeout / HTTP code / reached);
#                         status 0 when the host answered at all, 1 when the transport failed
#
# This only explains. Whether the session works is 42ctl's verdict (`auth me`); a host that answers
# here while 42ctl fails is a bad session, not a network fault (C16).
#
# Caveat: curl's exit code names the first failing layer only, and a captive proxy that answers 200
# for everything reads as "reached". Under-reporting a fault; the verdict still comes from 42ctl.
# Caveat: the 8-second ceiling is a guess; a slow link reads as a timeout.

v42_net_explain() {
  local code rc
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "$1" 2>/dev/null </dev/null)"
  rc=$?
  case "$rc" in
    0) printf 'the authority answered HTTP %s, so the network is fine' "$code" ;;
    6) printf 'DNS cannot resolve the authority host' && return 1 ;;
    7) printf 'the authority refused the connection (nothing listening, or a firewall)' && return 1 ;;
    28) printf 'the authority did not answer within 8 seconds (timeout)' && return 1 ;;
    35 | 51 | 58 | 60 | 77) printf 'the TLS handshake with the authority failed (curl exit %s)' "$rc" && return 1 ;;
    *) printf 'curl exit %s reaching the authority' "$rc" && return 1 ;;
  esac
}
