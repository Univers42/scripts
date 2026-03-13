#!/usr/bin/env python3
"""md-to-pdf.py — Markdown + Mermaid to Professional PDF (WeasyPrint + Kroki).

Content styling is driven by an external CSS theme (default: theme.css).
Cover styling is a separate CSS file in the ``covers/`` folder.

Usage examples::

    python3 md-to-pdf.py README.md
    python3 md-to-pdf.py README.md --cover minimal
    python3 md-to-pdf.py README.md --cover editorial
    python3 md-to-pdf.py README.md --cover gradient
    python3 md-to-pdf.py README.md --theme custom.css
    python3 md-to-pdf.py README.md --no-cover
    python3 md-to-pdf.py --list-covers

Quick-start::

    python3 -m venv .venv && source .venv/bin/activate
    pip install -U pip weasyprint markdown requests
    python3 scripts/md-to-pdf/md-to-pdf.py README.md
"""

import argparse
import base64
import hashlib
import os
import re
import sys
import time
import zlib
from collections import defaultdict
from datetime import date
from pathlib import Path

import markdown
import requests
from weasyprint import HTML

KROKI_URL = "https://kroki.io"
CACHE_DIR = Path(__file__).parent / ".mermaid-cache"
DEFAULT_THEME = Path(__file__).parent / "theme.css"
COVERS_DIR = Path(__file__).parent / "covers"
DEFAULT_COVER = "noir"
TIMEOUT = 60
DELAY = 1.2

_MD_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]*\)")


def strip_md_markup(text: str) -> str:
    """Strip Markdown link syntax and inline formatting from a heading.

    Removes ``[text](url)`` links, ``**bold**``, ``*italic*``, and
    back-tick ``code`` spans so that only the visible text remains.

    :param text: Raw Markdown heading text.
    :returns: Plain text with all inline Markdown removed.
    """
    text = _MD_LINK_RE.sub(r"\1", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"\*(.+?)\*", r"\1", text)
    text = re.sub(r"`(.+?)`", r"\1", text)
    return text.strip()


def slugify(text: str) -> str:
    """Convert a Markdown heading into a URL-safe slug.

    The result is used as the ``id`` attribute on HTML headings and as the
    ``href`` anchor in the table-of-contents.  Both call-sites feed raw
    Markdown text so the slugs always match.

    :param text: Raw Markdown heading text.
    :returns: Lowercase, hyphen-separated slug string.
    """
    s = strip_md_markup(text)
    s = re.sub(r"<[^>]+>", "", s)
    s = s.replace("\u2014", "-").replace("\u2013", "-")
    s = re.sub(r"&[a-zA-Z]+;", "", s)
    s = s.lower()
    s = re.sub(r"[\s_]+", "-", s)
    s = re.sub(r"[^\w-]", "", s)
    s = re.sub(r"-+", "-", s)
    return s.strip("-")


def build_toc(md_text: str) -> str:
    """Build an HTML table-of-contents from raw Markdown.

    Scans every line for ``##`` and ``###`` headings, skipping any that read
    "Table of Contents" or "Table des matières".  Nested ``<ol>`` elements
    give the TOC a two-level hierarchy.

    :param md_text: Full Markdown source (before HTML conversion).
    :returns: HTML string of the ``<nav class="toc">`` block, or ``""``
              if no headings are found.
    """
    items: list[tuple[int, str, str]] = []

    for line in md_text.splitlines():
        m2 = re.match(r"^##\s+(.+?)\s*$", line)
        m3 = re.match(r"^###\s+(.+?)\s*$", line)
        if m2:
            t = m2.group(1)
            if re.search(r"table of contents|table des matières", t, re.I):
                continue
            clean = strip_md_markup(t)
            if not clean:
                continue
            items.append((2, clean, slugify(t)))
        elif m3:
            t = m3.group(1)
            clean = strip_md_markup(t)
            if not clean:
                continue
            items.append((3, clean, slugify(t)))

    if not items:
        return ""

    lines: list[str] = [
        '<nav class="toc">',
        '<h2 class="toc-title">Table of Contents</h2>',
        '<ol class="toc-root">',
    ]
    in_sub = False

    for level, title, slug in items:
        safe_title = (
            title.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        )
        if level == 2:
            if in_sub:
                lines.append("      </ol>")
                lines.append("    </li>")
                in_sub = False
            lines.append('  <li class="toc-h2">')
            lines.append(
                f'    <a href="#{slug}">'
                f'<span class="toc-num"></span>{safe_title}</a>'
            )
        else:
            if not in_sub:
                lines.append('    <ol class="toc-sub">')
                in_sub = True
            lines.append(
                f'      <li class="toc-h3">'
                f'<a href="#{slug}">{safe_title}</a></li>'
            )

    if in_sub:
        lines += ["      </ol>", "    </li>"]
    else:
        lines.append("  </li>")

    lines += ["</ol>", "</nav>"]
    return "\n".join(lines) + "\n"


def add_heading_ids(html: str) -> str:
    """Inject ``id`` attributes into ``<h1>``–``<h3>`` elements.

    Uses the same :func:`slugify` logic as :func:`build_toc` so that TOC
    anchor links resolve correctly.  Duplicate slugs receive a numeric
    suffix (e.g. ``foo-1``).

    :param html: Body HTML produced by the Markdown engine.
    :returns: The same HTML with ``id="…"`` added to each heading.
    """
    slug_counts: dict[str, int] = defaultdict(int)

    def _repl(m: re.Match) -> str:
        tag = m.group(1)
        attrs = m.group(2)
        inner = m.group(3)

        if "id=" in (attrs or ""):
            return m.group(0)

        plain = re.sub(r"<[^>]+>", "", inner)
        base_slug = slugify(plain)

        count = slug_counts[base_slug]
        slug_counts[base_slug] += 1
        final = base_slug if count == 0 else f"{base_slug}-{count}"

        new_attrs = f' id="{final}"'
        if attrs and attrs.strip():
            new_attrs += f" {attrs.strip()}"
        return f"<{tag}{new_attrs}>{inner}</{tag}>"

    return re.sub(
        r"<(h[1-3])([ \t][^>]*)?>(.+?)</\1>",
        _repl,
        html,
        flags=re.DOTALL,
    )


def _strip_emoji(text: str) -> str:
    """Remove emoji and symbol characters from Mermaid diagram source.

    Kroki's renderer sometimes chokes on emoji codepoints, so they are
    stripped before the diagram is sent to the API.

    :param text: Raw Mermaid diagram source.
    :returns: Cleaned diagram source without emoji.
    """
    return re.compile(
        r"[\U0001F300-\U0001FAFF\U00002702-\U000027B0\U000024C2-\U0001F251"
        r"\u2600-\u27BF\uFE0F\u200D]+",
        re.UNICODE,
    ).sub("", text)


def render_mermaid(code: str, no_cache: bool = False) -> str | None:
    """Render a Mermaid diagram to a base-64 encoded PNG via Kroki.io.

    Tries a compact GET request first (for diagrams <= 2000 chars), then
    falls back to POST.  Results are cached on disk by content hash so
    unchanged diagrams are never re-rendered.

    :param code:     Mermaid diagram source code.
    :param no_cache: When ``True``, ignore and overwrite cached images.
    :returns: Base-64 string of the PNG, or ``None`` on total failure.
    """
    CACHE_DIR.mkdir(exist_ok=True)
    key = hashlib.sha256(code.encode()).hexdigest()[:16]
    path = CACHE_DIR / f"{key}.png"

    if not no_cache and path.exists() and path.stat().st_size > 500:
        print(f"   ♻  Cache: {key}")
        return base64.b64encode(path.read_bytes()).decode()

    print(f"   🎨  Rendering via Kroki ({len(code)} chars)…")
    png = None

    if len(code) <= 2000:
        for attempt in range(2):
            try:
                enc = base64.urlsafe_b64encode(
                    zlib.compress(code.encode("utf-8"), 9)
                ).decode()
                r = requests.get(
                    f"{KROKI_URL}/mermaid/png/{enc}", timeout=TIMEOUT
                )
                r.raise_for_status()
                png = r.content
                print(f"   ✓  {len(png) // 1024} KB (GET)")
                break
            except Exception as e:
                print(f"   ⚠  GET {attempt + 1}: {e}")
                time.sleep(DELAY)

    if not png:
        for attempt in range(3):
            try:
                time.sleep(DELAY)
                r = requests.post(
                    f"{KROKI_URL}/mermaid/png",
                    json={"diagram_source": code},
                    headers={"Content-Type": "application/json"},
                    timeout=TIMEOUT,
                )
                r.raise_for_status()
                png = r.content
                print(f"   ✓  {len(png) // 1024} KB (POST)")
                break
            except Exception as e:
                print(f"   ⚠  POST {attempt + 1}: {e}")
                time.sleep(DELAY * (attempt + 1))

    if png:
        path.write_bytes(png)
        return base64.b64encode(png).decode()

    print("   ✗  All attempts failed — using code-block fallback")
    return None


def replace_mermaid_blocks(md_text: str, no_cache: bool = False) -> str:
    """Replace every fenced mermaid block with an inline PNG image.

    Each fenced block is sent to :func:`render_mermaid`.  On success the
    image is embedded as a data-URI; on failure a ``<pre>`` code-block
    fallback is inserted instead.

    :param md_text:  Full Markdown source.
    :param no_cache: Forward to :func:`render_mermaid`.
    :returns: Markdown with Mermaid fences replaced by HTML ``<div>`` blocks.
    """
    n = [0]

    def _sub(m: re.Match) -> str:
        n[0] += 1
        code = _strip_emoji(m.group(1).strip())
        print(f"\n   [{n[0]}] Diagram…")
        b64 = render_mermaid(code, no_cache)
        if b64:
            return (
                f'\n<div class="diagram">'
                f'<img src="data:image/png;base64,{b64}" '
                f'alt="Diagram {n[0]}"/>'
                f"</div>\n"
            )
        esc = (
            code.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
        )
        return (
            f'\n<div class="diagram-fallback">'
            f"<pre><code>{esc}</code></pre></div>\n"
        )

    return re.compile(r"```mermaid\s*\n([\s\S]*?)```").sub(_sub, md_text)


def _in_fence(lines: list[str], i: int) -> bool:
    """Return ``True`` if line *i* sits inside a fenced code block.

    Counts the number of triple-backtick openers that appear before line *i*.
    An odd count means the line is inside a fence.

    :param lines: All lines of the Markdown document.
    :param i:     Zero-based index of the line to test.
    :returns: Whether the line is inside a fenced code block.
    """
    return (
        sum(1 for j in range(i) if lines[j].rstrip().startswith("```")) % 2 == 1
    )


def fix_blockquote_linebreaks(text: str) -> str:
    """Append trailing double-spaces to consecutive blockquote lines.

    Markdown requires two trailing spaces for a hard line-break.  Without
    this fix, successive ``>`` lines collapse into a single paragraph inside
    the rendered blockquote.

    :param text: Full Markdown source.
    :returns: Markdown with hard breaks inserted between blockquote lines.
    """
    lines = text.split("\n")
    result: list[str] = []
    for i, line in enumerate(lines):
        s = line.rstrip()
        if (
            s.startswith(">")
            and not _in_fence(lines, i)
            and i + 1 < len(lines)
            and lines[i + 1].rstrip().startswith(">")
            and not s.endswith("  ")
        ):
            result.append(s + "  ")
        else:
            result.append(line)
    return "\n".join(result)


_CALLOUT_RE = re.compile(
    r"^>\s*\[!(\w+)\]\s*(.*?)$",
    re.IGNORECASE,
)

CALLOUT_DEFAULTS: dict[str, tuple[str, str]] = {
    "note":      ("Note",      "📝"),
    "info":      ("Info",      "ℹ️"),
    "tip":       ("Tip",       "💡"),
    "success":   ("Success",   "✅"),
    "check":     ("Check",     "✅"),
    "done":      ("Done",      "✅"),
    "warning":   ("Warning",   "⚠️"),
    "caution":   ("Caution",   "⚠️"),
    "attention": ("Attention", "⚠️"),
    "danger":    ("Danger",    "🔴"),
    "error":     ("Error",     "❌"),
    "failure":   ("Failure",   "❌"),
    "fail":      ("Fail",      "❌"),
    "bug":       ("Bug",       "🐛"),
    "example":   ("Example",   "📎"),
    "quote":     ("Quote",     "💬"),
    "cite":      ("Quote",     "💬"),
    "question":  ("Question",  "❓"),
    "help":      ("Help",      "❓"),
    "faq":       ("FAQ",       "❓"),
    "abstract":  ("Abstract",  "📋"),
    "summary":   ("Summary",   "📋"),
    "tldr":      ("TL;DR",    "📋"),
    "todo":      ("To-Do",     "☑️"),
}

_CALLOUT_ALIAS: dict[str, str] = {
    "check": "success",
    "done": "success",
    "attention": "warning",
    "caution": "warning",
    "error": "danger",
    "failure": "danger",
    "fail": "danger",
    "cite": "quote",
    "help": "question",
    "faq": "question",
    "summary": "abstract",
    "tldr": "abstract",
}


def _md_inline(text: str) -> str:
    """Render a small Markdown fragment to HTML.

    Used to process callout body content so that inline formatting
    (bold, code, links, lists, etc.) is preserved inside the callout
    ``<div>``.

    :param text: Markdown fragment (typically a few lines).
    :returns: Rendered HTML string.
    """
    return markdown.markdown(
        text,
        extensions=["tables", "fenced_code", "sane_lists", "smarty", "attr_list"],
        output_format="html5",
    )


def convert_callouts(text: str) -> str:
    """Convert Obsidian-style callouts to styled HTML ``<div>`` blocks.

    Scans for lines matching ``> [!type] Optional title`` and collects all
    subsequent blockquote-continuation lines as the body.  Each callout is
    emitted as a self-contained HTML block *before* the Markdown engine
    runs, so the divs pass through untouched.

    Supported canonical types: note, info, tip, success, warning, danger,
    bug, example, quote, question, abstract, todo.  Aliases (e.g. caution,
    error, cite, faq, tldr) are mapped to their canonical type for CSS
    class selection.

    :param text: Full Markdown source.
    :returns: Markdown with callout blockquotes replaced by HTML divs.
    """
    lines = text.split("\n")
    result: list[str] = []
    i = 0

    while i < len(lines):
        line = lines[i]

        if _in_fence(lines, i):
            result.append(line)
            i += 1
            continue

        m = _CALLOUT_RE.match(line)
        if not m:
            result.append(line)
            i += 1
            continue

        raw_type = m.group(1).lower()
        custom_title = m.group(2).strip()

        canon = _CALLOUT_ALIAS.get(raw_type, raw_type)
        default_title, default_emoji = CALLOUT_DEFAULTS.get(
            raw_type, (raw_type.title(), "📌")
        )

        title = custom_title if custom_title else default_title
        emoji = default_emoji

        body_lines: list[str] = []
        i += 1
        while i < len(lines):
            s = lines[i].rstrip()
            if s.startswith("> "):
                body_lines.append(s[2:])
                i += 1
            elif s == ">":
                body_lines.append("")
                i += 1
            else:
                break

        body_md = "\n".join(body_lines).strip()
        body_html = _md_inline(body_md) if body_md else ""

        safe_title = (
            title.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        )

        html_parts = [
            f'\n<div class="callout callout-{canon}">',
            '<div class="callout-header">',
            f'<span class="callout-icon">{emoji}</span>',
            f'<span class="callout-title">{safe_title}</span>',
            "</div>",
            '<div class="callout-body">',
            body_html,
            "</div>",
            "</div>\n",
        ]

        result.append("\n".join(html_parts))

    return "\n".join(result)


def fix_list_separation(text: str) -> str:
    """Insert blank lines before list items that follow a prose paragraph.

    Some Markdown renderers require a blank line before the first ``-`` or
    ``1.`` to correctly start a list.  This pre-processor adds one when a
    list item directly follows a non-list, non-heading line.

    :param text: Full Markdown source.
    :returns: Markdown with blank lines inserted where needed.
    """
    lines = text.split("\n")
    result: list[str] = []
    _list = re.compile(r"^\s*[-*]\s|^\s*\d+\.\s")

    for i, line in enumerate(lines):
        if _list.match(line.rstrip()) and not _in_fence(lines, i) and i > 0:
            prev = lines[i - 1].rstrip()
            if prev and not _list.match(prev) and not prev.startswith("#"):
                result.append("")
        result.append(line)

    return "\n".join(result)


def build_cover_html(
    title: str, subtitle: str, author: str, today: str
) -> str:
    """Generate the HTML for the cover page.

    The cover is an Apple-inspired hero layout whose visual style is
    entirely controlled by CSS tokens defined in the active cover
    stylesheet.  This function only provides the structural markup.

    :param title:    Document title (may contain an em-dash separator).
    :param subtitle: Document subtitle (may be empty).
    :param author:   Author name (may be empty).
    :param today:    Formatted date string for the cover footer.
    :returns: Complete HTML string for the cover ``<div>``.
    """
    parts = re.split(r"\s[—–:]\s", title, maxsplit=1)
    main = parts[0].replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    accent_html = ""
    if len(parts) > 1:
        a = parts[1].replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        accent_html = f'<span class="cover-title-accent">{a}</span>'

    sub_html = f'<p class="cover-sub">{subtitle}</p>' if subtitle else ""
    auth_html = (
        f'<div class="meta-row">'
        f'<span class="meta-k">Author</span>'
        f'<span class="meta-v">{author}</span>'
        f"</div>"
        if author
        else ""
    )

    return f"""<div class="cover">

      <header class="cover-header">
        <div class="brand-logo"></div>
        <div class="doc-badge"></div>
      </header>

      <div class="cover-body">
        <p class="cover-eyebrow">Documentation</p>
        <h1 class="cover-h1">{main}{accent_html}</h1>
        {sub_html}
        <div class="cover-rule"></div>
        <div class="cover-meta">
          {auth_html}
          <div class="meta-row"><span class="meta-k">Date</span><span class="meta-v">{today}</span></div>
        </div>
      </div>

      <div class="cover-foot">
        <span class="cover-foot-text"></span>
        <span class="cover-foot-dots">● ● ●</span>
      </div>
    </div>
"""


def resolve_cover(name: str) -> Path | None:
    """Resolve a cover name to its CSS file path.

    Accepts either a bare name (e.g. ``"noir"``) that is looked up in
    :data:`COVERS_DIR`, or a direct filesystem path ending in ``.css``.

    :param name: Cover name or CSS file path.
    :returns: Resolved :class:`~pathlib.Path`, or ``None`` if not found.
    """
    if not name:
        return None
    p = Path(name)
    if p.suffix == ".css" and p.exists():
        return p
    candidate = COVERS_DIR / f"{name}.css"
    if candidate.exists():
        return candidate
    return None


def list_covers() -> list[str]:
    """Return a sorted list of available cover style names.

    Scans the :data:`COVERS_DIR` directory for ``.css`` files and returns
    their stems (filenames without extension).

    :returns: Sorted list of cover names, e.g. ``["editorial", "gradient", "noir"]``.
    """
    if not COVERS_DIR.is_dir():
        return []
    return sorted(p.stem for p in COVERS_DIR.glob("*.css"))


def load_css(
    theme_path: Path,
    doc_title: str,
    cover_name: str | None = DEFAULT_COVER,
) -> str:
    """Load the content CSS theme and optional cover CSS.

    Reads the content theme from *theme_path*, appends the cover
    stylesheet if *cover_name* resolves, and replaces every occurrence of
    the placeholder ``DOC_TITLE`` with the actual document title (used by
    CSS ``content:`` rules for running headers/footers).

    :param theme_path: Path to the main content CSS file.
    :param doc_title:  Document title for placeholder substitution.
    :param cover_name: Cover style name or ``None`` to skip.
    :returns: Combined CSS string ready for ``<style>`` injection.
    """
    if not theme_path.exists():
        print(f"   ⚠  Theme not found: {theme_path} — using minimal fallback")
        css = "body { font-family: sans-serif; font-size: 10pt; }"
    else:
        css = theme_path.read_text(encoding="utf-8")

    if cover_name:
        cover_path = resolve_cover(cover_name)
        if cover_path:
            css += "\n\n/* ── Cover: " + cover_path.stem + " ── */\n"
            css += cover_path.read_text(encoding="utf-8")
            print(f"🎭  Cover  : {cover_path.stem}  ({cover_path})")
        else:
            print(f"   ⚠  Cover '{cover_name}' not found — no cover style loaded")

    safe = doc_title.replace('"', '\\"')
    return css.replace("DOC_TITLE", safe)


def build_html(
    title: str,
    subtitle: str,
    author: str,
    show_cover: bool,
    today: str,
    toc_html: str,
    body_html: str,
    theme_path: Path = DEFAULT_THEME,
    cover_name: str | None = DEFAULT_COVER,
) -> str:
    """Assemble the complete HTML document for PDF rendering.

    Combines the cover page, table of contents, and body content into a
    single self-contained HTML string with an inline ``<style>`` block.

    :param title:      Document title.
    :param subtitle:   Document subtitle (may be empty).
    :param author:     Author name (may be empty).
    :param show_cover: Whether to include the cover page.
    :param today:      Formatted date string.
    :param toc_html:   Pre-built TOC HTML (from :func:`build_toc`).
    :param body_html:  Converted Markdown body HTML.
    :param theme_path: Path to the CSS content theme.
    :param cover_name: Cover style name (or ``None``).
    :returns: Full ``<!DOCTYPE html>`` string.
    """
    safe_title = (
        title.replace('"', "&quot;").replace("<", "&lt;").replace(">", "&gt;")
    )
    cover_html = (
        build_cover_html(title, subtitle, author, today) if show_cover else ""
    )
    css = load_css(theme_path, safe_title, cover_name if show_cover else None)

    reset_html = '<div class="page-reset"></div>' if show_cover else ""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>{safe_title}</title>
<style>{css}</style>
</head>
<body>
{cover_html}
{reset_html}
{toc_html}
{body_html}
</body>
</html>"""


def convert(args: argparse.Namespace) -> None:
    """Run the full Markdown-to-PDF conversion pipeline.

    Orchestrates every stage: metadata extraction, TOC generation, callout
    conversion, Mermaid diagram rendering, Markdown-to-HTML conversion,
    heading-ID injection, HTML assembly, and final PDF output via
    WeasyPrint.

    :param args: Parsed command-line arguments from :mod:`argparse`.
    """
    if getattr(args, "list_covers", False):
        covers = list_covers()
        if covers:
            print("\n🎭  Available cover styles:\n")
            for name in covers:
                marker = " ◀ default" if name == DEFAULT_COVER else ""
                print(f"   • {name}{marker}")
            print(f"\n   ({COVERS_DIR})\n")
        else:
            print(f"\n   ⚠  No covers found in {COVERS_DIR}\n")
        return

    input_path = args.input
    output_path = args.output or re.sub(r"\.md$", ".pdf", input_path)
    theme_path = Path(args.theme) if args.theme else DEFAULT_THEME
    cover_name = args.cover if args.cover else DEFAULT_COVER
    today = date.today().strftime("%B %d, %Y")

    print(f"\n📄  Input  : {input_path}")
    print(f"📦  Output : {output_path}")
    print(f"🎨  Theme  : {theme_path}")
    if not args.no_cover:
        print(f"🎭  Cover  : {cover_name}")
    print()

    md_text = Path(input_path).read_text(encoding="utf-8")
    print(f"📖  Read {len(md_text):,} chars")

    title_match = re.search(r"^#\s+(.+)$", md_text, re.M)
    title = args.title or (
        title_match.group(1).strip() if title_match else "Document"
    )

    subtitle = args.subtitle or ""
    if not subtitle and title_match:
        after_title = md_text[title_match.end():]
        sub_match = re.match(r"\s*\n\*([^*\n]+)\*\s*$", after_title, re.M)
        if sub_match:
            subtitle = sub_match.group(1).strip()

    author = args.author or ""

    print(f"📌  Title    : {title}")
    print(f"   Subtitle : {subtitle or '(none)'}")
    print(f"   Author   : {author or '(none)'}")

    toc_html = build_toc(md_text)
    print(f"📑  TOC: {toc_html.count('<li')} entries")

    md_text = re.sub(
        r"^## Table of Contents\s*\n[\s\S]*?(?=\n## |\n---|\Z)",
        "",
        md_text,
        flags=re.M,
    )
    md_text = re.sub(
        r"^## Table des matières\s*\n[\s\S]*?(?=\n## |\n---|\Z)",
        "",
        md_text,
        flags=re.M,
    )

    md_text = convert_callouts(md_text)
    md_text = fix_blockquote_linebreaks(md_text)
    md_text = fix_list_separation(md_text)

    if args.no_cache and CACHE_DIR.exists():
        for f in CACHE_DIR.iterdir():
            f.unlink()
        print("🗑  Cleared diagram cache")

    count = len(re.findall(r"```mermaid", md_text))
    print(f"\n🎨  Found {count} Mermaid diagram(s)")
    md_text = replace_mermaid_blocks(md_text, args.no_cache)

    print("\n📝  Converting Markdown → HTML…")
    body_html = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "sane_lists", "smarty", "attr_list"],
        output_format="html5",
    )

    body_html = add_heading_ids(body_html)

    full_html = build_html(
        title,
        subtitle,
        author,
        not args.no_cover,
        today,
        toc_html,
        body_html,
        theme_path,
        cover_name,
    )

    html_path = re.sub(r"\.pdf$", ".html", output_path)
    Path(html_path).write_text(full_html, encoding="utf-8")
    print(f"🔍  Debug HTML → {html_path}")

    print("\n🖨  Generating PDF with WeasyPrint…")
    HTML(
        string=full_html, base_url=str(Path(input_path).parent)
    ).write_pdf(output_path)

    kb = os.path.getsize(output_path) / 1024
    print(f"\n✅  Done → {output_path}  ({kb:.0f} KB)\n")


if __name__ == "__main__":
    p = argparse.ArgumentParser(
        description="Convert Markdown (+ Mermaid) to a styled PDF."
    )
    p.add_argument("input", nargs="?", default=None, help="Input .md file")
    p.add_argument("output", nargs="?")
    p.add_argument("--title", help="Override document title")
    p.add_argument("--subtitle", help="Override subtitle")
    p.add_argument("--author", help="Author name for cover page")
    p.add_argument(
        "--theme",
        help="Path to a custom CSS content theme (default: theme.css)",
    )
    p.add_argument(
        "--cover",
        help=(
            f"Cover style name or path (default: {DEFAULT_COVER}). "
            f"Available: {', '.join(list_covers()) or 'none'}"
        ),
    )
    p.add_argument(
        "--list-covers",
        action="store_true",
        help="List available cover styles and exit",
    )
    p.add_argument("--no-cover", action="store_true")
    p.add_argument("--no-cache", action="store_true")
    args = p.parse_args()

    if args.list_covers:
        convert(args)
        sys.exit(0)

    if not args.input:
        p.error("the following arguments are required: input")

    if not Path(args.input).exists():
        print(f"✗  File not found: {args.input}")
        sys.exit(1)

    convert(args)
