# shellcheck shell=bash
# config.sh — `vault42 config show`: the effective, parsed configuration after the known-pair
# environment overrides. Defines functions only; sourced by vault42.sh.

cmd_config() {
  [ "${1:-}" = show ] || {
    usage_error "usage: vault42 config show"
    return 2
  }
  v42_config_show
}
