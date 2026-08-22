#!/usr/bin/env python3
"""Strip comments and whitespace pollution from a C/C++ tree.

Why a tokenizer and not a regex
-------------------------------
A regex-based comment stripper is wrong on real code, and quietly so::

    const char* url  = "https://example.org";     // '//' inside a string
    const char* g    = "middle = nospcrlfcl\\n";   // escapes
    const char* path = "/* not a comment */";     // literal braces
    char slash = '/';                             // char literal

Every one of those is mangled by the obvious regex. This walks a small state
machine instead (code / line comment / block comment / string / char), so a
comment is only ever recognised in code context.

Modes
-----
    --dry-run     report what would change, touch nothing   [default]
    --apply       rewrite the files in place

    --comments    strip comments                            [default: on]
    --no-comments whitespace only

    --keep-header keep each file's leading comment block (42 header, licence)
    --keep-todo   keep TODO / FIXME / XXX / HACK / NOTE lines

Whitespace fixes are always applied when writing: trailing whitespace removed,
runs of blank lines collapsed to one, exactly one final newline, tabs left
alone (they are meaningful in Makefiles and this tool never edits those).

Exit status is 1 in --dry-run when something would change, so it works as a CI
gate; 0 after a successful --apply.
"""

import argparse
import os
import sys

CODE, LINE_COMMENT, BLOCK_COMMENT, STRING, CHAR = range(5)

SOURCE_EXTENSIONS = (".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx",
                     ".tpp", ".ipp")

KEEP_MARKERS = ("TODO", "FIXME", "XXX", "HACK", "NOTE")

# Google's own linter (cpplint, readability/namespace) REQUIRES a namespace to
# be closed with `}  // namespace Foo`. Stripping those is not "cleaner" -- it
# is a style violation the linter reports. So they survive even a full strip;
# they are structural markers, not prose.
STRUCTURAL_PREFIXES = ("// namespace", "//namespace")


def split_comments(text):
    """Return (code_text, spans) where spans are (start, end) of comments.

    The state machine is the whole point: `//` and `/*` are only comment
    openers while in CODE state, so they stay untouched inside a string or a
    character literal.
    """
    spans = []
    state = CODE
    i = 0
    n = len(text)
    start = 0

    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if state == CODE:
            if c == "/" and nxt == "/":
                state, start = LINE_COMMENT, i
                i += 2
                continue
            if c == "/" and nxt == "*":
                state, start = BLOCK_COMMENT, i
                i += 2
                continue
            if c == '"':
                state = STRING
            elif c == "'":
                state = CHAR
            i += 1

        elif state == LINE_COMMENT:
            # A backslash-newline continues a // comment onto the next line.
            if c == "\\" and nxt == "\n":
                i += 2
                continue
            if c == "\n":
                spans.append((start, i))
                state = CODE
                continue
            i += 1

        elif state == BLOCK_COMMENT:
            if c == "*" and nxt == "/":
                spans.append((start, i + 2))
                state = CODE
                i += 2
                continue
            i += 1

        elif state == STRING:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                state = CODE
            i += 1

        elif state == CHAR:
            if c == "\\":
                i += 2
                continue
            if c == "'":
                state = CODE
            i += 1

    if state == LINE_COMMENT:
        spans.append((start, n))
    elif state == BLOCK_COMMENT:
        # Unterminated block comment: refuse rather than guess.
        raise ValueError("unterminated block comment")

    return spans


def should_keep(text, span, args, is_first):
    body = text[span[0]:span[1]]
    if body.strip().startswith(STRUCTURAL_PREFIXES):
        return True
    if args.keep_header and is_first:
        return True
    if args.keep_todo and any(m in body for m in KEEP_MARKERS):
        return True
    return False


def strip_comments(text, args):
    spans = split_comments(text)
    if not spans:
        return text

    # A comment is "leading" only if nothing but whitespace precedes it, so
    # only the very first span can ever qualify.
    first_index = 0 if text[:spans[0][0]].strip() == "" else None

    out = []
    prev = 0
    for k, (a, b) in enumerate(spans):
        if should_keep(text, (a, b), args, is_first=(k == first_index)):
            continue
        out.append(text[prev:a])
        # A comment between code on one line leaves a gap; keep one space so
        # `int a;/*x*/int b;` does not become `int a;int b;` -- harmless, and
        # it keeps tokens apart in the pathological case.
        out.append(" " if text[prev:a].strip() and not text[a - 1:a].isspace()
                   else "")
        prev = b
    out.append(text[prev:])
    return "".join(out)


ACCESS_SPECIFIERS = ("public:", "private:", "protected:")


def tidy_whitespace(text):
    """Whitespace fixes, including the blank-line rules cpplint enforces.

    Removing a comment usually strands the blank line that separated it, and
    cpplint flags those (whitespace/blank_line): no blank after an opening
    brace or an access specifier, none before a closing brace. Left alone, a
    full strip more than doubles the linter's error count -- measured on this
    tree: 41 findings before, 93 after.
    """
    lines = [ln.rstrip() for ln in text.split("\n")]

    collapsed = []
    blank = 0
    for ln in lines:
        if ln == "":
            blank += 1
            if blank > 1:
                continue
        else:
            blank = 0
        collapsed.append(ln)

    # No blank line directly after "{" or an access specifier.
    pruned = []
    for ln in collapsed:
        if ln == "" and pruned:
            prev = pruned[-1].strip()
            if prev.endswith("{") or prev in ACCESS_SPECIFIERS:
                continue
        pruned.append(ln)

    # No blank line directly before a lone closing brace.
    collapsed = []
    for i, ln in enumerate(pruned):
        if ln == "":
            nxt = pruned[i + 1].strip() if i + 1 < len(pruned) else ""
            if nxt in ("}", "};"):
                continue
        collapsed.append(ln)

    while collapsed and collapsed[0] == "":
        collapsed.pop(0)
    while collapsed and collapsed[-1] == "":
        collapsed.pop()

    return "\n".join(collapsed) + "\n" if collapsed else ""


def process(path, args):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        original = fh.read()

    text = original
    if args.comments:
        try:
            text = strip_comments(text, args)
        except ValueError as exc:
            return None, "%s: %s" % (path, exc)
    text = tidy_whitespace(text)

    if text == original:
        return False, None

    if args.apply:
        with open(path, "w", encoding="utf-8",
                  errors="surrogateescape") as fh:
            fh.write(text)
    return True, None


def collect(roots, excludes):
    found = []
    for root in roots:
        if os.path.isfile(root):
            found.append(root)
            continue
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs
                       if not any(os.path.join(base, d).startswith(x)
                                  for x in excludes)
                       and d not in (".git", "obj", "build")]
            for name in sorted(files):
                if name.endswith(SOURCE_EXTENSIONS):
                    full = os.path.join(base, name)
                    if not any(full.startswith(x) for x in excludes):
                        found.append(full)
    return found


def main():
    ap = argparse.ArgumentParser(
        description="Strip C/C++ comments and whitespace pollution.")
    ap.add_argument("paths", nargs="*", default=["src", "include"],
                    help="files or directories (default: src include)")
    ap.add_argument("--apply", action="store_true",
                    help="rewrite files in place (default is a dry run)")
    ap.add_argument("--dry-run", dest="apply", action="store_false",
                    help="report only (default)")
    ap.add_argument("--no-comments", dest="comments", action="store_false",
                    help="whitespace only, keep every comment")
    ap.add_argument("--keep-header", action="store_true",
                    help="keep each file's leading comment block")
    ap.add_argument("--keep-todo", action="store_true",
                    help="keep TODO/FIXME/XXX/HACK/NOTE comments")
    ap.add_argument("--exclude", action="append", default=[],
                    help="path prefix to skip (repeatable)")
    ap.set_defaults(apply=False, comments=True)
    args = ap.parse_args()

    excludes = [os.path.normpath(x) for x in args.exclude]
    files = collect(args.paths, excludes)
    if not files:
        print("no source files found", file=sys.stderr)
        return 1

    changed, errors = [], []
    for path in files:
        result, err = process(path, args)
        if err:
            errors.append(err)
        elif result:
            changed.append(path)

    for err in errors:
        print("error: %s" % err, file=sys.stderr)

    verb = "rewrote" if args.apply else "would change"
    print("%s %d of %d file(s)" % (verb, len(changed), len(files)))
    for path in changed:
        print("  %s" % path)

    if errors:
        return 2
    if changed and not args.apply:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
