#!/usr/bin/env python3
"""Strip comments (and whitespace pollution) from a source tree, any language.

Why a per-language tokenizer and not a regex
--------------------------------------------
A regex-based comment stripper is wrong on real code, and quietly so::

    const char* url  = "https://example.org";     // '//' inside a string
    const char* g    = "middle = nospcrlfcl\\n";   // escapes
    const char* path = "/* not a comment */";     // literal delimiters
    char slash = '/';                             // char literal
    re = /https:\\/\\//;                            // '//' inside a JS regex
    echo "value #1"          # '#' inside a shell string, not a comment
    url: http://host#frag    # YAML: no space before '#' -> not a comment
    x = 1 // 2               # Python floor division, not a comment

Every one of those is mangled by the obvious regex. This walks a small state
machine per language instead (code / line comment / block comment / string /
char / regex / heredoc / embedded language), so a comment is only ever
recognised in real code context.

Supported out of the box
------------------------
C, C++, C#, Java, Kotlin, Scala, Swift, Go, Rust, JavaScript/TypeScript,
JSONC/JSON5, CSS, SCSS/Sass/Less, HTML/XML/SVG/Vue (incl. embedded
<script>/<style>), PHP (incl. the HTML around it and here/nowdoc), Shell
(incl. heredocs and $'...'), YAML, TOML, INI/conf, Python (keeps docstrings),
Ruby, Perl (incl. POD), SQL, Lua, Haskell, OCaml, R, PowerShell, Lisp/Clojure,
Vim, Dockerfile, Makefile (opt-in). Extend LANGS / EXT_LANG to add more.

Modes
-----
    --dry-run     report what would change, touch nothing   [default]
    --apply       rewrite the files in place

    --comments    strip comments                            [default: on]
    --no-comments whitespace only

    --keep-header keep each file's leading comment block (licence / 42 header)
    --keep-todo   keep TODO / FIXME / XXX / HACK / NOTE lines
    --makefiles   also process Makefiles (off by default: recipe '#' is subtle)

Shebang lines (`#!...`) and editor modelines (`-*- ... -*-`, `vim:`) are always
kept. Whitespace is always tidied on write: trailing whitespace removed, runs
of blank lines collapsed to one, exactly one final newline, leading/trailing
blank lines dropped. Content inside multi-line strings and heredocs is left
byte-for-byte intact.

Exit status is 1 in --dry-run when something would change (so it works as a CI
gate), 2 on a parse error, 0 otherwise.
"""

import argparse
import os
import re
import sys

VERSION = "2.0"

KEEP_MARKERS = ("TODO", "FIXME", "XXX", "HACK", "NOTE")
MODELINE_HINTS = ("-*-", "vim:", "vi:", "ex:", "coding:", "coding=")


# --------------------------------------------------------------------------- #
# Language model
# --------------------------------------------------------------------------- #
class Str(object):
    """One kind of string / character literal."""

    __slots__ = ("open", "close", "esc", "newline", "raw", "dbl")

    def __init__(self, open, close=None, esc=True, newline=False, raw=False,
                 dbl=False):
        self.open = open
        self.close = close if close is not None else open
        self.esc = esc            # backslash escapes the next char
        self.newline = newline    # may span lines (=> a protected region)
        self.raw = raw            # no escape processing at all
        self.dbl = dbl            # doubled close delimiter is a literal ('')


class Lang(object):
    def __init__(self, name, kind="generic", line=(), line_mode="any",
                 ws_seps=" \t\n", line_escape=False, block=(), strings=(),
                 braces=False, struct_prefixes=(), sol_blocks=(),
                 cut_markers=(), pod=False, shell_heredoc=False,
                 php_heredoc=False, php_hash_guard=False, py_strings=False,
                 rust_raw=False, js_regex=False):
        self.name = name
        self.kind = kind                      # generic | html | php
        self.line = tuple(line)
        self.line_mode = line_mode            # any | ws | sol
        self.ws_seps = set(ws_seps)
        self.line_escape = line_escape        # a backslash before it cancels it
        self.block = tuple(block)             # (open, close, nested)
        self.strings = tuple(strings)
        self.braces = braces                  # apply brace blank-line tidy
        self.struct_prefixes = tuple(struct_prefixes)
        self.sol_blocks = tuple(sol_blocks)   # (open, close) anchored at col 0
        self.cut_markers = tuple(cut_markers)  # rest of file is data past here
        self.pod = pod                        # Perl =word ... =cut
        self.shell_heredoc = shell_heredoc
        self.php_heredoc = php_heredoc
        self.php_hash_guard = php_hash_guard  # '#[' is an attribute, not a note
        self.py_strings = py_strings          # r/b/f/u string prefixes
        self.rust_raw = rust_raw              # r"..." r#"..."#
        self.js_regex = js_regex              # /.../ regex literals


LANGS = {}


def _mk(name, **kw):
    LANGS[name] = Lang(name, **kw)


Q2 = (Str('"'), Str("'"))
CBLOCK = (("/*", "*/", False),)
CSTRUCT = ("// namespace", "//namespace", "//<")

# C family and friends -------------------------------------------------------
_mk("c", line=("//",), block=CBLOCK, strings=Q2, braces=True,
    struct_prefixes=CSTRUCT)
_mk("cpp", line=("//",), block=CBLOCK, strings=Q2, braces=True,
    struct_prefixes=CSTRUCT)
_mk("csharp", line=("//",), block=CBLOCK, braces=True,
    strings=(Str('"""', esc=False, newline=True), Str('@"', '"', esc=False),
             Str('"'), Str("'")))
_mk("java", line=("//",), block=CBLOCK, braces=True,
    strings=(Str('"""', newline=True), Str('"'), Str("'")))
_mk("kotlin", line=("//",), block=CBLOCK, braces=True,
    strings=(Str('"""', esc=False, newline=True), Str('"'), Str("'")))
_mk("scala", line=("//",), block=CBLOCK, braces=True,
    strings=(Str('"""', esc=False, newline=True), Str('"'), Str("'")))
_mk("swift", line=("//",), block=CBLOCK, braces=True,
    strings=(Str('"""', newline=True), Str('"')))
_mk("go", line=("//",), block=CBLOCK, braces=True,
    strings=(Str('`', esc=False, newline=True), Str('"'), Str("'")))
_mk("rust", line=("//",), block=(("/*", "*/", True),), braces=True,
    rust_raw=True, strings=(Str('"'), Str("'")))
_mk("js", line=("//",), block=CBLOCK, braces=True, js_regex=True,
    strings=(Str('`', newline=True), Str('"'), Str("'")))
_mk("jsonc", line=("//",), block=CBLOCK, braces=True, strings=(Str('"'),))

# Stylesheets --------------------------------------------------------------- #
_mk("css", block=CBLOCK, strings=Q2, braces=True)
_mk("scss", line=("//",), block=CBLOCK, strings=Q2, braces=True)

# Markup ------------------------------------------------------------------- #
_mk("html", kind="html")
_mk("xml", kind="html")
_mk("php", kind="php")
_mk("_php_inner", line=("//", "#"), block=CBLOCK, strings=(Str('"'), Str("'")),
    braces=True, php_hash_guard=True, php_heredoc=True)

# Shell ------------------------------------------------------------------- #
_mk("shell", line=("#",), line_mode="ws", ws_seps=" \t\n;&|(`",
    shell_heredoc=True,
    strings=(Str("$'", "'", esc=True), Str("'", esc=False), Str('"'),
             Str('`', esc=False, newline=True)))

# Config ---------------------------------------------------------------- #
_mk("yaml", line=("#",), line_mode="ws", ws_seps=" \t\n",
    strings=(Str('"'), Str("'", esc=False, dbl=True)))
_mk("toml", line=("#",),
    strings=(Str('"""', newline=True), Str("'''", esc=False, newline=True),
             Str('"'), Str("'", esc=False)))
_mk("ini", line=("#", ";"), line_mode="sol")
_mk("cnf", line=("#", ";"), line_mode="sol")
_mk("conf", line=("#",), line_mode="ws", ws_seps=" \t\n", strings=Q2)
_mk("dockerfile", line=("#",), line_mode="sol")
_mk("makefile", line=("#",), line_escape=True)

# Scripting ------------------------------------------------------------- #
_mk("python", line=("#",), py_strings=True,
    strings=(Str('"""', newline=True), Str("'''", newline=True),
             Str('"'), Str("'")))
_mk("ruby", line=("#",), strings=Q2, sol_blocks=(("=begin", "=end"),),
    cut_markers=("__END__",))
_mk("perl", line=("#",), strings=Q2, pod=True,
    cut_markers=("__END__", "__DATA__"))
_mk("r", line=("#",), strings=Q2)
_mk("powershell", line=("#",), block=(("<#", "#>", False),), strings=Q2)
_mk("lua", line=("--",), block=(("--[[", "]]", False),),
    strings=(Str('"'), Str("'"), Str("[[", "]]", esc=False, newline=True)))
_mk("perl_pod", line=("#",))  # placeholder, unused directly

# Functional / other -------------------------------------------------- #
_mk("haskell", line=("--",), block=(("{-", "-}", True),), strings=(Str('"'),))
_mk("ocaml", block=(("(*", "*)", True),), strings=(Str('"'),))
_mk("lisp", line=(";",), block=(("#|", "|#", True),), strings=(Str('"'),))
_mk("sql", line=("--", "#"), block=CBLOCK,
    strings=(Str("'", esc=False, dbl=True, newline=True),
             Str('"', esc=False, dbl=True)))
_mk("vim", line=('"',), line_mode="sol")


EXT_LANG = {
    ".c": "c", ".h": "c", ".i": "c",
    ".cc": "cpp", ".cpp": "cpp", ".cxx": "cpp", ".c++": "cpp", ".hpp": "cpp",
    ".hh": "cpp", ".hxx": "cpp", ".h++": "cpp", ".tpp": "cpp", ".ipp": "cpp",
    ".inl": "cpp",
    ".cs": "csharp",
    ".java": "java", ".kt": "kotlin", ".kts": "kotlin", ".scala": "scala",
    ".sc": "scala", ".swift": "swift", ".go": "go", ".rs": "rust",
    ".js": "js", ".mjs": "js", ".cjs": "js", ".jsx": "js", ".ts": "js",
    ".tsx": "js", ".mts": "js", ".cts": "js",
    ".jsonc": "jsonc", ".json5": "jsonc",
    ".css": "css", ".scss": "scss", ".sass": "scss", ".less": "scss",
    ".html": "html", ".htm": "html", ".xhtml": "html", ".vue": "html",
    ".svelte": "html",
    ".xml": "xml", ".svg": "xml", ".xsl": "xml", ".xslt": "xml",
    ".plist": "xml", ".resx": "xml", ".csproj": "xml", ".props": "xml",
    ".targets": "xml", ".xaml": "xml", ".wxs": "xml",
    ".php": "php", ".phtml": "php", ".php3": "php", ".php4": "php",
    ".php5": "php", ".php7": "php",
    ".sh": "shell", ".bash": "shell", ".zsh": "shell", ".ksh": "shell",
    ".ash": "shell", ".dash": "shell",
    ".yml": "yaml", ".yaml": "yaml",
    ".toml": "toml",
    ".ini": "ini", ".cfg": "ini", ".properties": "ini",
    ".cnf": "cnf",
    ".conf": "conf",
    ".py": "python", ".pyi": "python", ".pyw": "python",
    ".rb": "ruby", ".rake": "ruby", ".gemspec": "ruby",
    ".pl": "perl", ".pm": "perl", ".pod": "perl", ".t": "perl",
    ".r": "r",
    ".ps1": "powershell", ".psm1": "powershell", ".psd1": "powershell",
    ".lua": "lua",
    ".hs": "haskell", ".lhs": "haskell",
    ".ml": "ocaml", ".mli": "ocaml",
    ".el": "lisp", ".lisp": "lisp", ".lsp": "lisp", ".clj": "lisp",
    ".cljs": "lisp", ".cljc": "lisp", ".scm": "lisp", ".ss": "lisp",
    ".sql": "sql",
    ".vim": "vim",
    ".mk": "makefile",
}

FILENAME_LANG = {
    "Makefile": "makefile", "GNUmakefile": "makefile", "makefile": "makefile",
    "Dockerfile": "dockerfile", "Containerfile": "dockerfile",
    "Gemfile": "ruby", "Rakefile": "ruby", "Vagrantfile": "ruby",
    "Brewfile": "ruby", "Guardfile": "ruby",
    ".bashrc": "shell", ".bash_profile": "shell", ".bash_aliases": "shell",
    ".bash_login": "shell", ".bash_logout": "shell", ".profile": "shell",
    ".zshrc": "shell", ".zprofile": "shell", ".zshenv": "shell",
    ".zlogin": "shell", ".kshrc": "shell", ".inputrc": "shell",
    ".vimrc": "vim", ".gvimrc": "vim", "_vimrc": "vim",
}

SHEBANG_LANG = [
    ("python", "python"), ("node", "js"), ("perl", "perl"), ("ruby", "ruby"),
    ("Rscript", "r"), ("pwsh", "powershell"), ("lua", "lua"),
    ("bash", "shell"), ("zsh", "shell"), ("ksh", "shell"), ("dash", "shell"),
    ("/sh", "shell"), (" sh", "shell"), ("env sh", "shell"),
]

SKIP_EXT = {
    ".md", ".markdown", ".mkd", ".rst", ".adoc", ".txt", ".text", ".json",
    ".lock", ".csv", ".tsv", ".log", ".pdf", ".png", ".jpg", ".jpeg", ".gif",
    ".webp", ".ico", ".bmp", ".svgz", ".woff", ".woff2", ".ttf", ".otf",
    ".eot", ".zip", ".gz", ".bz2", ".xz", ".tar", ".7z", ".jar", ".war",
    ".class", ".o", ".obj", ".a", ".so", ".dylib", ".dll", ".exe", ".bin",
    ".pyc", ".pyo", ".map", ".min", ".wasm", ".ppm", ".pgm",
}

DEFAULT_EXCLUDE_DIRS = {
    ".git", ".hg", ".svn", "node_modules", "bower_components", "vendor",
    "third_party", "vendored", ".venv", "venv", "env", ".tox", ".mypy_cache",
    ".pytest_cache", "__pycache__", "build", "dist", "obj", "out", "target",
    ".next", ".nuxt", ".cache", ".idea", ".vscode", "coverage",
}

MAX_BYTES = 5 * 1024 * 1024

_HEREDOC_RE = re.compile(
    r"<<(?P<dash>-?)[ \t]*\\?(?P<q>['\"]?)(?P<delim>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?P=q)")
_PHP_HEREDOC_RE = re.compile(
    r"<<<[ \t]*(?P<q>['\"]?)(?P<delim>[A-Za-z_][A-Za-z0-9_]*)(?P=q)[ \t]*\r?\n")
_PY_PREFIX_RE = re.compile(r"[rRbBfFuU]{1,2}(?=(\"\"\"|'''|\"|'))")
_RUST_RAW_RE = re.compile(r'r(#*)"')
_REGEX_PREFIX = set("(=,:;[!&|?{}~^%<>+-*/") | {"return", "typeof", "in", "of",
                                               "new", "delete", "void",
                                               "throw", "case", "yield",
                                               "await", "do", "else"}


# --------------------------------------------------------------------------- #
# Low-level scanners
# --------------------------------------------------------------------------- #
def _scan_block(text, i, op, cl, nested):
    n = len(text)
    depth = 1
    j = i + len(op)
    while j < n:
        if nested and text.startswith(op, j):
            depth += 1
            j += len(op)
            continue
        if text.startswith(cl, j):
            depth -= 1
            j += len(cl)
            if depth == 0:
                return j
            continue
        j += 1
    raise ValueError("unterminated block comment")


def _scan_string(text, i, s):
    """Return (end, ok, multiline). ok=False => not really a string here."""
    n = len(text)
    j = i + len(s.open)
    ml = False
    while j < n:
        ch = text[j]
        if ch == "\n":
            if s.newline:
                ml = True
                j += 1
                continue
            return i + 1, False, False
        if not s.raw and s.esc and ch == "\\":
            j += 2
            continue
        if text.startswith(s.close, j):
            k = j + len(s.close)
            if s.dbl and text.startswith(s.close, k):
                j = k + len(s.close)
                continue
            return k, True, ml
        j += 1
    if s.newline:
        return n, True, ml
    return i + 1, False, False


def _py_string_at(text, i):
    if i > 0 and (text[i - 1].isalnum() or text[i - 1] == "_"):
        return None
    m = _PY_PREFIX_RE.match(text, i)
    if not m:
        return None
    pfx = m.group(0)
    raw = "r" in pfx or "R" in pfx
    q0 = m.end()
    for q in ('"""', "'''", '"', "'"):
        if text.startswith(q, q0):
            s = Str(q, esc=not raw, newline=(len(q) == 3), raw=raw)
            end, ok, ml = _scan_string(text, q0, s)
            if not ok:
                return None
            return end, ml
    return None


def _rust_raw_at(text, i):
    if i > 0 and (text[i - 1].isalnum() or text[i - 1] == "_"):
        return None
    m = _RUST_RAW_RE.match(text, i)
    if not m:
        return None
    close = '"' + m.group(1)
    end = text.find(close, i + m.end())
    if end == -1:
        return None
    end += len(close)
    return end, (text.find("\n", i, end) != -1)


def _line_ok(text, i, mk, lang):
    if lang.line_escape and i > 0 and text[i - 1] == "\\":
        return False
    mode = lang.line_mode
    if mode == "any":
        if lang.php_hash_guard and mk == "#" and text[i:i + 2] == "#[":
            return False
        return True
    if mode == "ws":
        return i == 0 or text[i - 1] in lang.ws_seps
    if mode == "sol":
        j = i - 1
        while j >= 0 and text[j] in " \t":
            j -= 1
        return j < 0 or text[j] == "\n"
    return True


def _last_sig(out_chars):
    """Last non-whitespace token fragment already emitted (for JS regex ctx)."""
    k = len(out_chars) - 1
    while k >= 0 and out_chars[k] in " \t\r\n":
        k -= 1
    if k < 0:
        return ""
    if out_chars[k].isalpha():
        w = []
        while k >= 0 and (out_chars[k].isalnum() or out_chars[k] == "_"):
            w.append(out_chars[k])
            k -= 1
        return "".join(reversed(w))
    return out_chars[k]


# --------------------------------------------------------------------------- #
# Span finders  ->  (comment_spans, protected_spans) in absolute coords
# --------------------------------------------------------------------------- #
def _fin(spans, prot):
    spans.sort()
    prot.sort()
    return spans, prot


def find_spans(text, lang, base=0):
    if lang.kind == "html":
        return _spans_html(text, base)
    if lang.kind == "php":
        return _spans_php(text, base)
    return _spans_generic(text, lang, base)


def _spans_generic(text, lang, base=0):
    spans = []
    prot = []
    i = 0
    n = len(text)
    pending = []                       # shell heredocs awaiting their body
    emitted = []                      # recent code chars, for JS regex context
    sopen = sorted(lang.strings, key=lambda s: -len(s.open))
    bopen = sorted(lang.block, key=lambda t: -len(t[0]))
    lopen = sorted(lang.line, key=lambda s: -len(s))

    while i < n:
        c = text[i]
        at_ls = i == 0 or text[i - 1] == "\n"

        # -- shell heredoc bodies: consume verbatim right after the newline ---
        if c == "\n" and pending:
            i = _consume_heredocs(text, i + 1, pending, prot, base)
            emitted.append("\n")
            continue

        # -- Perl POD / Ruby =begin, anchored at column 0 --------------------
        if at_ls and (lang.sol_blocks or lang.pod):
            end = _match_sol_block(text, i, lang)
            if end is not None:
                spans.append((base + i, base + end))
                i = end
                continue

        # -- cut markers: __END__ / __DATA__ -------------------------------- #
        if at_ls and lang.cut_markers:
            cut = _match_cut(text, i, lang)
            if cut is not None:
                spans.append((base + i, base + n))
                return _fin(spans, prot)

        # -- block comments ------------------------------------------------- #
        hit = False
        for op, cl, nested in bopen:
            if text.startswith(op, i):
                end = _scan_block(text, i, op, cl, nested)
                spans.append((base + i, base + end))
                i = end
                hit = True
                break
        if hit:
            continue

        # -- line comments ----------------------------------------------- #
        for mk in lopen:
            if text.startswith(mk, i) and _line_ok(text, i, mk, lang):
                le = text.find("\n", i)
                end = le if le != -1 else n
                spans.append((base + i, base + end))
                i = end
                hit = True
                break
        if hit:
            continue

        # -- strings --------------------------------------------------- #
        for s in sopen:
            if text.startswith(s.open, i):
                end, ok, ml = _scan_string(text, i, s)
                if ok and end > i:
                    if ml:
                        prot.append((base + i, base + end))
                    emitted.append("x")
                    i = end
                    hit = True
                    break
                # not a string (e.g. Rust lifetime 'a): treat as a bare char
                emitted.append(c)
                i += 1
                hit = True
                break
        if hit:
            continue

        # -- Python r/b/f string prefixes -------------------------------- #
        if lang.py_strings and c in "rRbBfFuU":
            r = _py_string_at(text, i)
            if r:
                end, ml = r
                if ml:
                    prot.append((base + i, base + end))
                emitted.append("x")
                i = end
                continue

        # -- Rust raw strings ------------------------------------------ #
        if lang.rust_raw and c == "r":
            r = _rust_raw_at(text, i)
            if r:
                end, ml = r
                if ml:
                    prot.append((base + i, base + end))
                emitted.append("x")
                i = end
                continue

        # -- JS regex literals: keep '//' and '/*' inside them safe ---- #
        if lang.js_regex and c == "/" and i + 1 < n and text[i + 1] not in "/*=":
            if _last_sig(emitted) in _REGEX_PREFIX or not emitted:
                end = _scan_regex(text, i)
                if end is not None:
                    emitted.append("x")
                    i = end
                    continue

        # -- shell heredoc opener ------------------------------------- #
        if lang.shell_heredoc and text.startswith("<<", i) \
                and not text.startswith("<<<", i):
            m = _HEREDOC_RE.match(text, i)
            if m:
                pending.append((m.group("delim"), bool(m.group("dash"))))
                emitted.append("x")
                i = m.end()
                continue

        # -- PHP here/nowdoc opener ---------------------------------- #
        if lang.php_heredoc and text.startswith("<<<", i):
            end = _php_heredoc(text, i, prot, base)
            if end is not None:
                emitted.append("x")
                i = end
                continue

        if c not in " \t\r\n":
            emitted.append(c)
        elif c == "\n":
            emitted.append("\n")
        i += 1

    return _fin(spans, prot)


def _scan_regex(text, i):
    n = len(text)
    j = i + 1
    in_class = False
    while j < n:
        ch = text[j]
        if ch == "\n":
            return None
        if ch == "\\":
            j += 2
            continue
        if ch == "[":
            in_class = True
        elif ch == "]":
            in_class = False
        elif ch == "/" and not in_class:
            j += 1
            while j < n and text[j].isalpha():   # flags
                j += 1
            return j
        j += 1
    return None


def _match_sol_block(text, i, lang):
    for op, cl in lang.sol_blocks:
        if text.startswith(op, i) and (i + len(op) >= len(text)
                                       or not text[i + len(op)].isalnum()
                                       or op[-1].isalnum()):
            k = i + len(op)
            while True:
                p = text.find(cl, k)
                if p == -1:
                    le = -1
                    break
                if p == 0 or text[p - 1] == "\n":
                    le = text.find("\n", p)
                    break
                k = p + len(cl)
            return len(text) if le == -1 else le
    if lang.pod and text[i] == "=" and i + 1 < len(text) \
            and text[i + 1].isalpha():
        p = i
        while True:
            nl = text.find("\n=cut", p)
            if nl == -1:
                return len(text)
            line_end = text.find("\n", nl + 1)
            return len(text) if line_end == -1 else line_end
    return None


def _match_cut(text, i, lang):
    for mk in lang.cut_markers:
        if text.startswith(mk, i):
            j = i + len(mk)
            if j == len(text) or text[j] in "\r\n":
                return i
    return None


def _consume_heredocs(text, pos, pending, prot, base):
    n = len(text)
    while pending and pos <= n:
        delim, dash = pending[0]
        body_start = pos
        j = pos
        term_end = None
        while j <= n:
            le = text.find("\n", j)
            if le == -1:
                le = n
            line = text[j:le]
            cand = line.lstrip("\t") if dash else line
            if cand == delim:
                term_end = le
                break
            if le == n:
                break
            j = le + 1
        if term_end is None:
            if n > body_start:
                prot.append((base + body_start, base + n))
            pending.clear()
            return n
        if term_end > body_start:
            prot.append((base + body_start, base + j))
        pending.pop(0)
        pos = term_end + 1 if term_end < n else n
    return pos


def _php_heredoc(text, i, prot, base):
    m = _PHP_HEREDOC_RE.match(text, i)
    if not m:
        return None
    delim = m.group("delim")
    body_start = m.end()
    n = len(text)
    j = body_start
    term_re = re.compile(r"[ \t]*" + re.escape(delim) + r"(?![A-Za-z0-9_])")
    while j <= n:
        le = text.find("\n", j)
        if le == -1:
            le = n
        ms = term_re.match(text, j)
        if ms:
            if ms.end() > body_start:
                prot.append((base + body_start, base + j))
            return ms.end()
        if le == n:
            break
        j = le + 1
    prot.append((base + body_start, base + n))
    return n


def _spans_html(text, base=0):
    spans = []
    prot = []
    i = 0
    n = len(text)
    low = text.lower()
    while i < n:
        if text.startswith("<!--", i):
            j = text.find("-->", i + 4)
            j = n if j == -1 else j + 3
            spans.append((base + i, base + j))
            i = j
            continue
        if text.startswith("<![CDATA[", i):
            j = text.find("]]>", i + 9)
            j = n if j == -1 else j + 3
            prot.append((base + i, base + j))
            i = j
            continue
        if low.startswith("<script", i) and _tag_boundary(text, i + 7):
            i = _embed(text, i, "script", "js", spans, prot, base, low)
            continue
        if low.startswith("<style", i) and _tag_boundary(text, i + 6):
            i = _embed(text, i, "style", "css", spans, prot, base, low)
            continue
        i += 1
    return _fin(spans, prot)


def _tag_boundary(text, k):
    return k >= len(text) or text[k] in " \t\r\n>/"


def _embed(text, i, tag, inner_lang, spans, prot, base, low):
    n = len(text)
    gt = text.find(">", i)
    if gt == -1:
        return n
    open_tag = low[i:gt]
    end = low.find("</" + tag, gt + 1)
    if end == -1:
        end = n
    # Non-JS <script type="application/json"> etc.: leave opaque.
    scannable = True
    if tag == "script":
        m = re.search(r'type\s*=\s*["\']?([^"\'>\s]+)', open_tag)
        if m and m.group(1) not in ("text/javascript", "module",
                                    "application/javascript",
                                    "text/babel", "text/jsx"):
            scannable = False
    if scannable and end > gt + 1:
        s2, p2 = find_spans(text[gt + 1:end], LANGS[inner_lang],
                            base=base + gt + 1)
        spans.extend(s2)
        prot.extend(p2)
    elif end > gt + 1:
        prot.append((base + gt + 1, base + end))
    return end


def _spans_php(text, base=0):
    spans = []
    prot = []
    i = 0
    n = len(text)
    low = text.lower()
    inner = LANGS["_php_inner"]
    while i < n:
        op = _find_php_open(text, low, i)
        seg_end = op if op is not None else n
        hs, hp = _spans_html(text[i:seg_end], base=base + i)
        spans.extend(hs)
        prot.extend(hp)
        if op is None:
            break
        taglen = 5 if low.startswith("<?php", op) else (
            3 if text.startswith("<?=", op) else 2)
        close = text.find("?>", op + taglen)
        body_end = n if close == -1 else close
        s2, p2 = _spans_generic(text[op + taglen:body_end], inner,
                                base=base + op + taglen)
        spans.extend(s2)
        prot.extend(p2)
        i = body_end if close == -1 else close + 2
    return _fin(spans, prot)


def _find_php_open(text, low, i):
    a = low.find("<?php", i)
    b = text.find("<?=", i)
    c = text.find("<?", i)
    cands = [x for x in (a, b, c) if x != -1]
    return min(cands) if cands else None


# --------------------------------------------------------------------------- #
# Rewriting
# --------------------------------------------------------------------------- #
def _merge(spans):
    if not spans:
        return []
    spans = sorted(spans)
    out = [list(spans[0][:2])]
    for sp in spans[1:]:
        a, b = sp[0], sp[1]
        if a <= out[-1][1]:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return [tuple(x) for x in out]


def _keep_comment(text, a, b, lang, args, is_first):
    body = text[a:b]
    if a == 0 and text[:2] == "#!":
        return True
    line_no = text.count("\n", 0, a)
    total = text.count("\n")
    if any(h in body for h in MODELINE_HINTS) and (line_no <= 2
                                                   or line_no >= total - 2):
        return True
    st = body.strip()
    if lang.struct_prefixes and st.startswith(lang.struct_prefixes):
        return True
    if args.keep_todo and any(m in body for m in KEEP_MARKERS):
        return True
    if args.keep_header and is_first:
        return True
    return False


def _remove_comments(text, spans, lang, args):
    n = len(text)
    first_start = spans[0][0] if text[:spans[0][0]].strip() == "" else -2
    edits = []
    for a, b in spans:
        if _keep_comment(text, a, b, lang, args, is_first=(a == first_start)):
            continue
        ls = text.rfind("\n", 0, a) + 1
        le = text.find("\n", b)
        if le == -1:
            le = n
        before = text[ls:a]
        after = text[b:le]
        if before.strip() == "" and after.strip() == "":
            end = le + 1 if le < n else n
            edits.append((ls, end, ""))
        else:
            a2 = a
            while a2 > ls and text[a2 - 1] in " \t":
                a2 -= 1
            repl = " " if (before.strip() and after.strip()) else ""
            edits.append((a2, b, repl))
    if not edits:
        return text
    edits.sort()
    out = []
    prev = 0
    for s, e, r in edits:
        if s < prev:
            continue
        out.append(text[prev:s])
        out.append(r)
        prev = e
    out.append(text[prev:])
    return "".join(out)


ACCESS_SPECIFIERS = ("public:", "private:", "protected:")
CLOSERS = ("}", "};", ")", ");", "],", "];", "},", "};")


def _brace_prune(lines):
    out = []
    for ln in lines:
        if ln == "" and out:
            p = out[-1].strip()
            if p.endswith("{") or p in ACCESS_SPECIFIERS:
                continue
        out.append(ln)
    pruned = []
    for k, ln in enumerate(out):
        if ln == "":
            nxt = out[k + 1].strip() if k + 1 < len(out) else ""
            if nxt in CLOSERS:
                continue
        pruned.append(ln)
    return pruned


def _tidy(text, lang, protected):
    lines = text.split("\n")
    ranges = _merge(protected)
    res = []
    blank = 0
    off = 0
    ri = 0
    for ln in lines:
        start = off
        end = off + len(ln)
        off = end + 1
        while ri < len(ranges) and ranges[ri][1] <= start:
            ri += 1
        guarded = ri < len(ranges) and ranges[ri][0] < end + 1 \
            and ranges[ri][1] > start
        if guarded:
            res.append(ln)
            blank = 0
            continue
        stripped = ln.rstrip()
        if stripped == "":
            blank += 1
            if blank > 1:
                continue
            res.append("")
        else:
            blank = 0
            res.append(stripped)
    if lang.braces:
        res = _brace_prune(res)
    while res and res[0] == "":
        res.pop(0)
    while res and res[-1] == "":
        res.pop()
    return "\n".join(res) + "\n" if res else ""


def transform(text, lang, args):
    spans, prot = find_spans(text, lang)
    if args.comments and spans:
        text = _remove_comments(text, _merge(spans), lang, args)
        try:
            _, prot = find_spans(text, lang)
        except ValueError:
            prot = []
    return _tidy(text, lang, prot)


# --------------------------------------------------------------------------- #
# File discovery / driver
# --------------------------------------------------------------------------- #
def lang_for(path, ext_map, allow_makefiles):
    base = os.path.basename(path)
    for ext, lname in ext_map.items():
        if base.endswith(ext) and lname in LANGS:
            return LANGS[lname]
    if base in FILENAME_LANG:
        name = FILENAME_LANG[base]
        if name == "makefile" and not allow_makefiles:
            return None
        return LANGS[name]
    if base == "Dockerfile" or base.startswith("Dockerfile.") \
            or base.endswith(".Dockerfile") or base.endswith(".dockerfile"):
        return LANGS["dockerfile"]
    low = base.lower()
    if low.startswith("makefile") or base.endswith(".mk"):
        return LANGS["makefile"] if allow_makefiles else None
    _, ext = os.path.splitext(base)
    ext = ext.lower()
    if ext in EXT_LANG:
        return LANGS[EXT_LANG[ext]]
    if ext in SKIP_EXT:
        return None
    if ext == "":
        try:
            with open(path, "rb") as fh:
                first = fh.readline(256).decode("utf-8", "replace")
        except OSError:
            return None
        if first.startswith("#!"):
            for needle, lname in SHEBANG_LANG:
                if needle in first:
                    return LANGS[lname]
    return None


def _skip_name(name):
    return (name.endswith((".min.js", ".min.css", ".bundle.js", ".map"))
            or name in ("package-lock.json", "yarn.lock",
                        "pnpm-lock.yaml", "composer.lock"))


def _looks_like_make(path):
    base = os.path.basename(path)
    return base.lower().startswith("makefile") or base.endswith(".mk")


def collect(paths, args):
    excl_dirs = set(DEFAULT_EXCLUDE_DIRS)
    for inc in args.include:
        excl_dirs.discard(os.path.basename(os.path.normpath(inc)))
    excl_prefix = [os.path.normpath(p) for p in args.exclude]

    def excluded(p):
        p = os.path.normpath(p)
        return any(p == x or p.startswith(x + os.sep) for x in excl_prefix)

    found = []
    for root in paths:
        if os.path.isfile(root):
            found.append(root)
            continue
        for base, dirs, names in os.walk(root):
            dirs[:] = sorted(d for d in dirs
                             if d not in excl_dirs
                             and not excluded(os.path.join(base, d)))
            for nm in sorted(names):
                full = os.path.join(base, nm)
                if not excluded(full) and not _skip_name(nm):
                    found.append(full)
    return found


def process(path, args):
    lang = lang_for(path, args.ext_map, args.makefiles)
    if lang is None:
        return "skip", None
    try:
        if os.path.getsize(path) > MAX_BYTES:
            return "skip", None
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        return "error", "%s: %s" % (path, exc)
    if b"\x00" in raw[:8192]:
        return "skip", None

    original = raw.decode("utf-8", "surrogateescape")
    crlf = "\r\n" in original
    work = original.replace("\r\n", "\n") if crlf else original
    try:
        out = transform(work, lang, args)
    except ValueError as exc:
        return "error", "%s: %s" % (path, exc)
    if crlf:
        out = out.replace("\n", "\r\n")
    if out == original:
        return "same", None
    if args.apply:
        with open(path, "w", encoding="utf-8", errors="surrogateescape",
                  newline="") as fh:
            fh.write(out)
    return "changed", (lang.name if args.stats else None)


def _parse_ext_map(items):
    out = {}
    for it in items:
        if "=" not in it:
            raise SystemExit("--map expects EXT=LANG, got %r" % it)
        ext, lname = it.split("=", 1)
        if lname not in LANGS:
            raise SystemExit("unknown language %r (see --list-languages)"
                             % lname)
        out[ext if ext.startswith(".") else "." + ext] = lname
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Strip comments from a source tree, any language.")
    ap.add_argument("paths", nargs="*", default=["."],
                    help="files or directories (default: .)")
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
    ap.add_argument("--makefiles", action="store_true",
                    help="also process Makefiles (off by default)")
    ap.add_argument("--exclude", action="append", default=[], metavar="PATH",
                    help="path prefix to skip (repeatable)")
    ap.add_argument("--include", action="append", default=[], metavar="DIR",
                    help="re-include an auto-excluded dir like vendor "
                         "(repeatable)")
    ap.add_argument("--map", action="append", default=[], metavar="EXT=LANG",
                    help="force an extension to a language (repeatable)")
    ap.add_argument("--stats", action="store_true",
                    help="print a per-language summary")
    ap.add_argument("--list-languages", action="store_true",
                    help="print supported languages and exit")
    ap.add_argument("--version", action="version",
                    version="strip_comments %s" % VERSION)
    ap.set_defaults(apply=False, comments=True)
    args = ap.parse_args(argv)

    if args.list_languages:
        names = sorted(n for n in LANGS if not n.startswith("_")
                       and n != "perl_pod")
        print(", ".join(names))
        exts = sorted(set(EXT_LANG) | {"." + k for k in ()})
        print("\nextensions: " + " ".join(exts))
        print("filenames:  " + " ".join(sorted(FILENAME_LANG)))
        return 0

    args.ext_map = _parse_ext_map(args.map)

    files = collect(args.paths, args)
    if not files:
        print("no files found", file=sys.stderr)
        return 1

    changed, errors, by_lang, skipped_mk = [], [], {}, []
    for path in files:
        result, info = process(path, args)
        if result == "error":
            errors.append(info)
        elif result == "changed":
            changed.append(path)
            if info:
                by_lang[info] = by_lang.get(info, 0) + 1
        elif result == "skip" and not args.makefiles and _looks_like_make(path):
            skipped_mk.append(path)

    for err in errors:
        print("error: %s" % err, file=sys.stderr)

    verb = "rewrote" if args.apply else "would change"
    print("%s %d of %d file(s)" % (verb, len(changed), len(files)))
    for path in changed:
        print("  %s" % path)
    if args.stats and by_lang:
        print("by language:")
        for name in sorted(by_lang):
            print("  %-12s %d" % (name, by_lang[name]))
    if skipped_mk:
        print("note: %d Makefile(s) skipped -- pass --makefiles to include "
              "them:" % len(skipped_mk), file=sys.stderr)
        for path in skipped_mk:
            print("  %s" % path, file=sys.stderr)

    if errors:
        return 2
    if changed and not args.apply:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
