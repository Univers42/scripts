# shellcheck shell=bash
# envfile.sh — read one KEY from a KEY=VALUE file. Sourced; sets no shell options.
#
#   get_env FILE KEY   print KEY's value (blanks around the name dropped, '=' in the value kept,
#                      one pair of surrounding quotes stripped); status 1 and nothing printed when
#                      the file, key or value is absent. The value is never logged.
#
# Caveat: only plain `KEY=value` lines are read. An `export KEY=…` line or a value spread over
# several lines reads as absent.

get_env() {
  local raw
  [ -f "$1" ] || return 1
  raw="$(ENVFILE_KEY="$2" awk '
    BEGIN { k = ENVIRON["ENVFILE_KEY"] }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      eq = index(line, "=")
      if (line ~ /^#/ || eq < 2) next
      name = substr(line, 1, eq - 1)
      sub(/[ \t]+$/, "", name)
      if (name != k) next
      val = substr(line, eq + 1)
      sub(/^[ \t]+/, "", val)
      print val
      found = 1
      exit
    }
    END { exit !found }' "$1")" || return 1
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}
