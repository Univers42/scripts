# shellcheck shell=bash
# creds.sh — credentials come from the ENVIRONMENT and nowhere else. Sourced; sets no shell options.
#
#   v42_cred WHAT          the value (passphrase|password|email|tenant|token); empty when unset.
#                          Canonical name first, alias only when the canonical one is unset.
#   v42_cred_name WHAT     the variable that supplied it (canonical, alias, or empty): for doctor.
#   v42_cred_require WHAT  status 5 and a message naming the canonical variable when WHAT is unset.
#   v42_with_creds LEVEL CMD…
#                          run CMD in a subshell whose environment holds exactly LEVEL's credentials:
#                            none     no credential of the five (and no S3 key)
#                            hook     FT_PASSPHRASE
#                            keystore FT_PASSPHRASE, plus FT_S3_KEY/FT_S3_SECRET when set
#                            login    keystore + FT_PASSWORD + FT_LOGIN_EMAIL (42ctl's spelling of FT_EMAIL)
#                            register login + FT_REGISTER_TOKEN (42ctl's spelling of VAULT42_REGISTER_TOKEN)
#
# No credential file is read, no value is printed, and a value only ever travels in a child's
# environment, never in an argv (a `env VAR=value cmd` would show it in /proc/<pid>/cmdline).
#
# Caveat: FT_TENANT is deliberately in no level: 42ctl has no environment variable for it, so
# `login` passes it as `--tenant`, which is visible in argv. A tenant name is not a secret.
# Caveat: the aliases exist for hosts that already export 42ctl's own spellings; setting both a
# canonical name and its alias to different values uses the canonical one.

declare -gA V42_CRED_NAMES=(
  [passphrase]="FT_PASSPHRASE VAULT42_PASSPHRASE"
  [password]="FT_PASSWORD"
  [email]="FT_EMAIL FT_LOGIN_EMAIL"
  [tenant]="FT_TENANT"
  [token]="VAULT42_REGISTER_TOKEN FT_REGISTER_TOKEN"
)

V42_CRED_ALL="FT_PASSPHRASE VAULT42_PASSPHRASE FT_PASSWORD FT_EMAIL FT_LOGIN_EMAIL FT_TENANT
VAULT42_REGISTER_TOKEN FT_REGISTER_TOKEN FT_S3_KEY FT_S3_SECRET"

v42_cred_name() {
  local name
  for name in ${V42_CRED_NAMES[$1]}; do
    [ -z "${!name:-}" ] || {
      printf '%s' "$name"
      return 0
    }
  done
  return 1
}

v42_cred() {
  local name
  name="$(v42_cred_name "$1")" || return 0
  printf '%s' "${!name}"
}

v42_cred_require() {
  local canonical="${V42_CRED_NAMES[$1]%% *}"
  [ -z "$(v42_cred_name "$1")" ] || return 0
  printf 'vault42: %s is not set; export it (credentials are read from the environment only, never from a file)\n' "$canonical" >&2
  return 5
}

# Values are read into locals BEFORE the scrub, then exported into the subshell only.
v42_with_creds() {
  local level="$1" passphrase password email token s3key s3secret name
  shift
  passphrase="$(v42_cred passphrase)"
  password="$(v42_cred password)"
  email="$(v42_cred email)"
  token="$(v42_cred token)"
  s3key="${FT_S3_KEY:-}"
  s3secret="${FT_S3_SECRET:-}"
  (
    for name in $V42_CRED_ALL; do unset "$name"; done
    case "$level" in
      none) ;;
      hook | keystore | login | register) [ -z "$passphrase" ] || export FT_PASSPHRASE="$passphrase" ;;
      *) exit 2 ;;
    esac
    case "$level" in
      keystore | login | register)
        [ -z "$s3key" ] || export FT_S3_KEY="$s3key"
        [ -z "$s3secret" ] || export FT_S3_SECRET="$s3secret"
        ;;
    esac
    case "$level" in
      login | register)
        [ -z "$password" ] || export FT_PASSWORD="$password"
        [ -z "$email" ] || export FT_LOGIN_EMAIL="$email"
        ;;
    esac
    [ "$level" != register ] || [ -z "$token" ] || export FT_REGISTER_TOKEN="$token"
    "$@"
  )
}
