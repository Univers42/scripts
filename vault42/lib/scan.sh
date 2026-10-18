# shellcheck shell=bash
# scan.sh — which files `42ctl env push` would upload from a project root, and which
# git-ignored files it would silently leave behind. Sourced; sets no shell options.
#
#   vault42_scan ROOT       every path (relative to ROOT, LC_ALL=C sorted) the scanner takes
#   vault42_unscanned ROOT  git-ignored regular files of ROOT and its checked-out submodules
#                           that vault42_scan does not list, build output excluded
#
# The scan is a hand mirror of 42ctl commit 4ee32f6 src/core/project.rs (walk,
# walk_repositories_inside, skip_dir, skip_file, is_secret_dir, glob_match, patterns_at).
# It exists so a push can be previewed, and diffed, without the 42ctl binary or the vault.
#
# Caveat: mirrors commit 4ee32f6 only. A 42ctl that changes SKIP_DIRS, skip_file or the
# piercing depth is not tracked, so this under- or over-reports until the lists below change.
# Caveat: the "declined" warnings 42ctl prints for skipped dirs holding candidates are not
# mirrored; this prints files only.
# Caveat: file names containing a newline are mangled (line-oriented plumbing). 42ctl takes them.
# Caveat: ROOT with a .42ctl/project.json whose patterns contain "/" makes 42ctl refuse to scan;
# here that is an error (exit 1), and malformed JSON is the same.
# Caveat: vault42_unscanned drops build output by directory NAME only (pkg is wasm-pack's), so a
# real secret kept under a directory called "out", "build" or "pkg" is never reported.
# Under-reporting; edit the list.
# Caveat: non-regular, non-symlink entries (fifo, socket) are taken like 42ctl does; the
# "regular file" wording in the docs is looser than the code.

_VAULT42_SCAN_SKIP_DIRS=(node_modules .git target dist build vendor .cache coverage __pycache__
  .next .venv .claude .vault baas.bak)

_VAULT42_UNSCANNED_BUILD_DIRS='node_modules|dist|target|build|\.astro|\.next|\.turbo|coverage|playwright-report|test-results|\.cache|__pycache__|\.vite|out|pkg|\.vault42|\.42ctl'

# Prints the patterns in force, one per line. 42ctl reads the marker's `patterns` array when the
# marker exists and refuses path-shaped ones.
_vault42_scan_patterns() {
  local marker="$1/.42ctl/project.json"
  if [ ! -e "$marker" ]; then
    printf '%s\n' '*.env*' '*.secrets'
    return 0
  fi
  local pats
  pats=$(jq -er '.patterns[]' "$marker") || {
    echo "scan: cannot read .patterns from $marker" >&2
    return 1
  }
  case $pats in
  */*)
    echo "scan: pattern in $marker names a path; 42ctl refuses it" >&2
    return 1
    ;;
  esac
  printf '%s\n' "$pats"
}

# Reads `find` records (type<TAB>relative path) and prints the ones to take as F<TAB>path,
# and the skipped directories as S<TAB>path. A secrets dir anywhere above a file (within this
# walk) takes it; `all` is the walk's starting flag. The glob's only wildcard is `*`, so each
# pattern becomes an anchored regex with every other character bracket-escaped.
_vault42_scan_decide() {
  V42_PATS="$1" awk -F'\t' -v all0="$2" '
    function rx(p,   i, c, out) {
      out = "^"
      for (i = 1; i <= length(p); i++) {
        c = substr(p, i, 1)
        if (c == "*") out = out ".*"
        else if (c == "^") out = out "\\^"
        else if (c == "\\") out = out "\\\\"
        else out = out "[" c "]"
      }
      return out "$"
    }
    BEGIN {
      n = split(ENVIRON["V42_PATS"], raw, "\n")
      for (i = 1; i <= n; i++) re[i] = rx(raw[i])
    }
    $1 == "S" { print; next }
    {
      path = $2
      k = split(path, part, "/")
      name = part[k]
      if (index(name, ".bak") || name ~ /\.stale$/) next
      take = all0 + 0
      for (j = 1; j < k && !take; j++) if (part[j] == "secrets" || part[j] == ".secrets") take = 1
      for (i = 1; i <= n && !take; i++) if (name ~ re[i]) take = 1
      if (take) print "F\t" path
    }'
}

# _vault42_scan_walk DIR PREFIX ALL PATTERNS — one tree walk, then one level of piercing into
# each skipped directory's immediate repositories (flag reset), recursively.
_vault42_scan_walk() {
  local dir="$1" prefix="$2" all="$3" pats="$4"
  local -a prune=() skipped=()
  local name kind path
  for name in "${_VAULT42_SCAN_SKIP_DIRS[@]}"; do
    prune+=(-o -name "$name")
  done

  while IFS=$'\t' read -r kind path; do
    if [ "$kind" = F ]; then
      printf '%s%s\n' "$prefix" "$path"
    else
      skipped+=("$dir/$path")
    fi
  done < <(
    find "$dir" -mindepth 1 \
      \( -type l -o \( -type d -name .42ctl \) \) -prune -o \
      \( -type d \( -false "${prune[@]}" \) -printf 'S\t%P\n' -prune \) -o \
      ! -type d -printf 'F\t%P\n' | _vault42_scan_decide "$pats" "$all"
  )

  [ "${#skipped[@]}" -gt 0 ] || return 0
  local repo
  while IFS= read -r repo; do
    path=${repo#"$dir"/}
    _vault42_scan_walk "$repo" "$prefix$path/" 0 "$pats"
  done < <(find "${skipped[@]}" -mindepth 2 -maxdepth 2 -name .git -printf '%h\n')
}

vault42_scan() {
  local root="${1:?vault42_scan: ROOT required}" pats base all=0
  [ -d "$root" ] || {
    echo "scan: not a directory: $root" >&2
    return 1
  }
  pats=$(_vault42_scan_patterns "$root") || return 1
  base=$(basename "$(cd "$root" && pwd)")
  case $base in secrets | .secrets) all=1 ;; esac
  _vault42_scan_walk "${root%/}" "" "$all" "$pats" | LC_ALL=C sort
}

# Ignored files of one repository, as paths relative to ROOT (PREFIX is the repo's own path).
_vault42_unscanned_repo() {
  local root="$1" repo_path="$2" prefix=""
  [ "$repo_path" = . ] || prefix="$repo_path/"
  git -C "$root/$repo_path" -c core.quotepath=off ls-files -o -i --exclude-standard |
    grep -Ev "(^|/)($_VAULT42_UNSCANNED_BUILD_DIRS)(/|\$)" |
    sed "s|^|$prefix|" || true
}

vault42_unscanned() {
  local root="${1:?vault42_unscanned: ROOT required}" scanned candidates rel
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  scanned=$(vault42_scan "$root") || return 1
  candidates=$(
    {
      _vault42_unscanned_repo "$root" .
      git -C "$root" submodule --quiet foreach --recursive "echo \"\$displaypath\"" 2>/dev/null |
        while IFS= read -r rel; do _vault42_unscanned_repo "$root" "$rel"; done
    } | LC_ALL=C sort -u
  )
  [ -n "$candidates" ] || return 0
  LC_ALL=C comm -23 <(printf '%s\n' "$candidates") <(printf '%s\n' "$scanned" | LC_ALL=C sort) |
    while IFS= read -r rel; do
      if [ -f "$root/$rel" ] && [ ! -L "$root/$rel" ]; then printf '%s\n' "$rel"; fi
    done
}
