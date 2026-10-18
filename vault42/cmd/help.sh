# shellcheck shell=bash
# help.sh — `vault42 help [command]`. Defines functions only; sourced by vault42.sh.

_help_overview() {
  cat <<'TXT'
vault42 — move a project's environment files through a 42ctl vault.

usage: vault42 [--config PATH] [--target NAME] [--kind env|secrets|volumes|all]... COMMAND [ARGS]

commands:
  doctor            check 42ctl, the environment, the session and your key (alias: status)
  login             log in with FT_EMAIL, FT_PASSWORD and FT_TENANT from the environment
  keys ls           who holds a key to each target's environment
  list              the files the vault holds
  diff              what a push or a pull would change, by size
  find PATTERN      which targets hold a file matching PATTERN
  pull [--apply] [--only PATH]...   preview, or restore, the vault's files (post_pull runs after --apply)
  push [--yes] [FILE...]            replace the vault's tree with this checkout, or push named files
  secret get|set PATH               read or write one vault secret (set reads stdin)
  config show       the effective configuration
  volumes list|capture|restore [--all]   docker volume archives, never part of the default kinds
  help [command]    this text

credentials come from the environment only: FT_PASSPHRASE (all but login), FT_PASSWORD, FT_EMAIL and
FT_TENANT (login). exit codes: 0 ok, 1 failed or refused, 2 usage or invalid config, 3 pushed to a
personal vault, 4 locked, 5 missing credential.
TXT
}

_help_topic() {
  case "$1" in
  doctor | status) echo "vault42 doctor — read-only checks. Exit 5 without FT_PASSPHRASE, 2 on an invalid config, 1 on any FAIL, else 0. FT_PASSWORD, FT_EMAIL and FT_TENANT are SKIP unless you run login." ;;
  login) echo "vault42 login — reads FT_EMAIL, FT_PASSWORD and FT_TENANT (42ctl's own spellings are derived for the child only). FT_TENANT travels as --tenant in argv." ;;
  keys) echo "vault42 keys ls — the key holders of each selected target, with their state." ;;
  list) echo "vault42 list [--target NAME] — the vault's files, size and private flag." ;;
  diff) echo "vault42 diff — +local only, -vault only, ~size differs. Size only: a same-size edit is not shown." ;;
  find) echo "vault42 find PATTERN — shell-style pattern over the vault's paths of every target." ;;
  pull) echo "vault42 pull [--apply] [--only PATH]... — a preview unless --apply. --kind limits it. Fixes print as: vault42 pull --apply --only PATH." ;;
  push) echo "vault42 push [--yes] [--personal] [--share PATH] [--private PAT] [FILE...] — replaces the target's tree. With FILE, only those files are pushed and BYTES and MODE are compared first." ;;
  secret) echo "vault42 secret get PATH | vault42 secret set PATH < value" ;;
  config) echo "vault42 config show — the effective, parsed configuration." ;;
  volumes) echo "vault42 volumes list | capture | restore [--all] — needs a target with kinds = volumes." ;;
  *) usage_error "no help for '$1'; run: vault42 help" ;;
  esac
}

cmd_help() {
  if [ "$#" -eq 0 ]; then _help_overview; else _help_topic "$1"; fi
}
