#!/usr/bin/env python3
"""
md-to-pdf.py  —  Markdown + Mermaid → Professional PDF  (WeasyPrint + Kroki)

Content styling is driven by an external CSS theme (default: theme.css).
Cover styling is a separate CSS file in the covers/ folder.

    python3 md-to-pdf.py README.md                        # noir cover
    python3 md-to-pdf.py README.md --cover minimal         # clean white
    python3 md-to-pdf.py README.md --cover editorial       # journal feel
    python3 md-to-pdf.py README.md --cover gradient        # bold purple
    python3 md-to-pdf.py README.md --theme custom.css      # custom content theme
    python3 md-to-pdf.py README.md --no-cover              # skip cover entirely
    python3 md-to-pdf.py --list-covers                     # show available covers

Quick-start:
    python3 -m venv .venv && source .venv/bin/activate
    pip install -U pip weasyprint markdown requests
    python3 scripts/md-to-pdf/md-to-pdf.py README.md
"""

import sys, re, base64, hashlib, os, time, zlib, argparse
from pathlib import Path
from datetime import date
from collections import defaultdict

import requests
import markdown
from weasyprint import HTML


# ── Config ────────────────────────────────────────────────────────────────
KROKI_URL      = "https://kroki.io"
CACHE_DIR      = Path(__file__).parent / ".mermaid-cache"
DEFAULT_THEME  = Path(__file__).parent / "theme.css"
COVERS_DIR     = Path(__file__).parent / "covers"
DEFAULT_COVER  = "noir"
TIMEOUT        = 60
DELAY          = 1.2


# ════════════════════════════════════════════════════════════════════════════
#  SHARED SLUGIFY — single definition, called everywhere
#  Input MUST be raw markdown text (never HTML-encoded text).
#  This ensures build_toc() hrefs and add_heading_ids() ids always match.
# ════════════════════════════════════════════════════════════════════════════
_MD_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]*\)")  # [text](url) → text

def strip_md_markup(text: str) -> str:
    """Strip markdown link syntax and inline formatting from heading text."""
    text = _MD_LINK_RE.sub(r"\1", text)        # [text](url) → text
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)  # **bold** → bold
    text = re.sub(r"\*(.+?)\*", r"\1", text)      # *italic* → italic
    text = re.sub(r"`(.+?)`", r"\1", text)        # `code` → code
    return text.strip()


def slugify(text: str) -> str:
    s = strip_md_markup(text)                     # strip markdown first
    s = re.sub(r"<[^>]+>", "", s)                 # strip HTML tags
    s = s.replace("\u2014", "-").replace("\u2013", "-")  # em/en-dash → hyphen
    s = re.sub(r"&[a-zA-Z]+;", "", s)             # strip HTML entities (&amp; &lt; …)
    s = s.lower()
    s = re.sub(r"[\s_]+", "-", s)                 # whitespace → hyphens
    s = re.sub(r"[^\w-]", "", s)                  # keep only word chars + hyphens
    s = re.sub(r"-+", "-", s)                     # collapse repeated hyphens
    return s.strip("-")


# ════════════════════════════════════════════════════════════════════════════
#  TOC BUILDER
#  Reads raw markdown lines (before any HTML encoding).
# ════════════════════════════════════════════════════════════════════════════
def build_toc(md_text: str) -> str:
    items = []
    for line in md_text.splitlines():
        m2 = re.match(r"^##\s+(.+?)\s*$", line)
        m3 = re.match(r"^###\s+(.+?)\s*$", line)
        if m2:
            t = m2.group(1)
            if re.search(r"table of contents|table des matières", t, re.I):
                continue
            clean = strip_md_markup(t)         # [Level 1](url) → Level 1
            if not clean:                      # skip empty headings like "## "
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

    lines = [
        '<nav class="toc">',
        '<h2 class="toc-title">Table of Contents</h2>',
        '<ol class="toc-root">',
    ]
    in_sub = False

    for level, title, slug in items:
        safe_title = title.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        if level == 2:
            if in_sub:
                lines.append("      </ol>")
                lines.append("    </li>")
                in_sub = False
            lines.append(f'  <li class="toc-h2">')
            lines.append(f'    <a href="#{slug}"><span class="toc-num"></span>{safe_title}</a>')
        else:
            if not in_sub:
                lines.append('    <ol class="toc-sub">')
                in_sub = True
            lines.append(f'      <li class="toc-h3"><a href="#{slug}">{safe_title}</a></li>')

    if in_sub:
        lines += ["      </ol>", "    </li>"]
    else:
        lines.append("  </li>")

    lines += ["</ol>", "</nav>"]
    return "\n".join(lines) + "\n"


# ════════════════════════════════════════════════════════════════════════════
#  HEADING ID INJECTOR
#  Adds id="…" to <h1>–<h3> using THE SAME slugify() as build_toc().
#  The inner HTML from the markdown library may contain &amp; etc.;
#  slugify() strips HTML entities, so both call sites produce identical slugs.
# ════════════════════════════════════════════════════════════════════════════
def add_heading_ids(html: str) -> str:
    slug_counts: dict[str, int] = defaultdict(int)

    def _repl(m: re.Match) -> str:
        tag      = m.group(1)   # h1, h2, or h3
        attrs    = m.group(2)   # any existing attributes (often empty)
        inner    = m.group(3)   # inner HTML content

        if "id=" in (attrs or ""):
            return m.group(0)   # already has an id

        # strip tags to get plain text, then slugify
        # slugify() handles &amp; etc. itself
        plain     = re.sub(r"<[^>]+>", "", inner)
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


# ════════════════════════════════════════════════════════════════════════════
#  MERMAID → PNG via Kroki.io
# ════════════════════════════════════════════════════════════════════════════
def _strip_emoji(text: str) -> str:
    return re.compile(
        r"[\U0001F300-\U0001FAFF\U00002702-\U000027B0\U000024C2-\U0001F251"
        r"\u2600-\u27BF\uFE0F\u200D]+", re.UNICODE
    ).sub("", text)


def render_mermaid(code: str, no_cache: bool = False) -> str | None:
    CACHE_DIR.mkdir(exist_ok=True)
    key  = hashlib.sha256(code.encode()).hexdigest()[:16]
    path = CACHE_DIR / f"{key}.png"

    if not no_cache and path.exists() and path.stat().st_size > 500:
        print(f"   ♻  Cache: {key}")
        return base64.b64encode(path.read_bytes()).decode()

    print(f"   🎨  Rendering via Kroki ({len(code)} chars)…")
    png = None

    if len(code) <= 2000:
        for attempt in range(2):
            try:
                enc = base64.urlsafe_b64encode(zlib.compress(code.encode("utf-8"), 9)).decode()
                r   = requests.get(f"{KROKI_URL}/mermaid/png/{enc}", timeout=TIMEOUT)
                r.raise_for_status()
                png = r.content
                print(f"   ✓  {len(png)//1024} KB (GET)")
                break
            except Exception as e:
                print(f"   ⚠  GET {attempt+1}: {e}")
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
                print(f"   ✓  {len(png)//1024} KB (POST)")
                break
            except Exception as e:
                print(f"   ⚠  POST {attempt+1}: {e}")
                time.sleep(DELAY * (attempt + 1))

    if png:
        path.write_bytes(png)
        return base64.b64encode(png).decode()

    print("   ✗  All attempts failed — using code-block fallback")
    return None


def replace_mermaid_blocks(md_text: str, no_cache: bool = False) -> str:
    n = [0]
    def _sub(m: re.Match) -> str:
        n[0] += 1
        code = _strip_emoji(m.group(1).strip())
        print(f"\n   [{n[0]}] Diagram…")
        b64 = render_mermaid(code, no_cache)
        if b64:
            return (f'\n<div class="diagram">'
                    f'<img src="data:image/png;base64,{b64}" alt="Diagram {n[0]}"/>'
                    f'</div>\n')
        esc = code.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
        return f'\n<div class="diagram-fallback"><pre><code>{esc}</code></pre></div>\n'
    return re.compile(r"```mermaid\s*\n([\s\S]*?)```").sub(_sub, md_text)


# ════════════════════════════════════════════════════════════════════════════
#  MARKDOWN PRE-PROCESSORS
# ════════════════════════════════════════════════════════════════════════════
def _in_fence(lines, i):
    return sum(1 for j in range(i) if lines[j].rstrip().startswith("```")) % 2 == 1

def fix_blockquote_linebreaks(text: str) -> str:
    lines, result = text.split("\n"), []
    for i, line in enumerate(lines):
        s = line.rstrip()
        if (s.startswith(">") and not _in_fence(lines, i)
                and i+1 < len(lines) and lines[i+1].rstrip().startswith(">")
                and not s.endswith("  ")):
            result.append(s + "  ")
        else:
            result.append(line)
    return "\n".join(result)

def fix_list_separation(text: str) -> str:
    lines, result = text.split("\n"), []
    _list = re.compile(r"^\s*[-*]\s|^\s*\d+\.\s")
    for i, line in enumerate(lines):
        if (_list.match(line.rstrip()) and not _in_fence(lines, i) and i > 0):
            prev = lines[i-1].rstrip()
            if prev and not _list.match(prev) and not prev.startswith("#"):
                result.append("")
        result.append(line)
    return "\n".join(result)


# ════════════════════════════════════════════════════════════════════════════
#  COVER HTML  (Apple-inspired generalist hero — all branding via CSS tokens)
# ════════════════════════════════════════════════════════════════════════════
def build_cover_html(title: str, subtitle: str, author: str, today: str) -> str:
    parts = re.split(r"\s[—–:]\s", title, maxsplit=1)
    main = parts[0].replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
    accent_html = ""
    if len(parts) > 1:
        a = parts[1].replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
        accent_html = f'<span class="cover-title-accent">{a}</span>'

    sub_html  = f'<p class="cover-sub">{subtitle}</p>' if subtitle else ""
    auth_html = (f'<div class="meta-row"><span class="meta-k">Author</span>'
                 f'<span class="meta-v">{author}</span></div>') if author else ""

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


# ════════════════════════════════════════════════════════════════════════════
#  CSS LOADER — combines content theme + cover style
# ════════════════════════════════════════════════════════════════════════════
def resolve_cover(name: str) -> Path | None:
    """Resolve a cover name (e.g. 'noir') to its CSS path, or None."""
    if not name:
        return None
    p = Path(name)
    if p.suffix == ".css" and p.exists():
        return p                       # absolute / relative path given
    candidate = COVERS_DIR / f"{name}.css"
    if candidate.exists():
        return candidate
    return None


def list_covers() -> list[str]:
    """Return sorted list of available cover names."""
    if not COVERS_DIR.is_dir():
        return []
    return sorted(p.stem for p in COVERS_DIR.glob("*.css"))


def load_css(theme_path: Path, doc_title: str, cover_name: str | None = DEFAULT_COVER) -> str:
    """Load content CSS + optional cover CSS, replacing the DOC_TITLE placeholder."""
    # ── Content theme ──
    if not theme_path.exists():
        print(f"   ⚠  Theme not found: {theme_path} — using minimal fallback")
        css = "body { font-family: sans-serif; font-size: 10pt; }"
    else:
        css = theme_path.read_text(encoding="utf-8")

    # ── Cover style ──
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


# ════════════════════════════════════════════════════════════════════════════
#  COMPLETE HTML DOCUMENT
# ════════════════════════════════════════════════════════════════════════════
def build_html(
    title: str, subtitle: str, author: str,
    show_cover: bool, today: str,
    toc_html: str, body_html: str,
    theme_path: Path = DEFAULT_THEME,
    cover_name: str | None = DEFAULT_COVER,
) -> str:
    safe_title  = title.replace('"', '&quot;').replace('<', '&lt;').replace('>', '&gt;')
    cover_html  = build_cover_html(title, subtitle, author, today) if show_cover else ""
    css         = load_css(theme_path, safe_title, cover_name if show_cover else None)

    # Page-counter reset: invisible element after cover forces page 1
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


# ════════════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════════════
def convert(args: argparse.Namespace) -> None:
    # ── Handle --list-covers ──
    if getattr(args, 'list_covers', False):
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

    input_path  = args.input
    output_path = args.output or re.sub(r"\.md$", ".pdf", input_path)
    theme_path  = Path(args.theme) if args.theme else DEFAULT_THEME
    cover_name  = args.cover if args.cover else DEFAULT_COVER
    today       = date.today().strftime("%B %d, %Y")

    print(f"\n📄  Input  : {input_path}")
    print(f"📦  Output : {output_path}")
    print(f"🎨  Theme  : {theme_path}")
    if not args.no_cover:
        print(f"🎭  Cover  : {cover_name}")
    print()

    md_text = Path(input_path).read_text(encoding="utf-8")
    print(f"📖  Read {len(md_text):,} chars")

    # Metadata
    title_match = re.search(r"^#\s+(.+)$", md_text, re.M)
    title       = args.title    or (title_match.group(1).strip() if title_match else "Document")

    # Subtitle: look for an italic line (*text*) immediately after the # title
    subtitle = args.subtitle or ""
    if not subtitle and title_match:
        after_title = md_text[title_match.end():]
        sub_match = re.match(r"\s*\n\*([^*\n]+)\*\s*$", after_title, re.M)
        if sub_match:
            subtitle = sub_match.group(1).strip()

    author      = args.author or ""

    print(f"📌  Title    : {title}")
    print(f"   Subtitle : {subtitle or '(none)'}")
    print(f"   Author   : {author   or '(none)'}")

    # Build TOC from original markdown (before any stripping)
    toc_html = build_toc(md_text)
    print(f"📑  TOC: {toc_html.count('<li')} entries")

    # Strip manual TOC sections
    md_text = re.sub(r"^## Table of Contents\s*\n[\s\S]*?(?=\n## |\n---|\Z)", "", md_text, flags=re.M)
    md_text = re.sub(r"^## Table des matières\s*\n[\s\S]*?(?=\n## |\n---|\Z)", "", md_text, flags=re.M)

    md_text = fix_blockquote_linebreaks(md_text)
    md_text = fix_list_separation(md_text)

    if args.no_cache and CACHE_DIR.exists():
        for f in CACHE_DIR.iterdir(): f.unlink()
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

    # Inject heading ids — uses same slugify as build_toc
    body_html = add_heading_ids(body_html)

    full_html = build_html(title, subtitle, author, not args.no_cover, today, toc_html, body_html, theme_path, cover_name)

    # Debug HTML
    html_path = re.sub(r"\.pdf$", ".html", output_path)
    Path(html_path).write_text(full_html, encoding="utf-8")
    print(f"🔍  Debug HTML → {html_path}")

    print("\n🖨  Generating PDF with WeasyPrint…")
    HTML(string=full_html, base_url=str(Path(input_path).parent)).write_pdf(output_path)

    kb = os.path.getsize(output_path) / 1024
    print(f"\n✅  Done → {output_path}  ({kb:.0f} KB)\n")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Convert Markdown (+ Mermaid) to a styled PDF.")
    p.add_argument("input",          nargs="?", default=None, help="Input .md file")
    p.add_argument("output",         nargs="?")
    p.add_argument("--title",        help="Override document title")
    p.add_argument("--subtitle",     help="Override subtitle")
    p.add_argument("--author",       help="Author name for cover page")
    p.add_argument("--theme",        help="Path to a custom CSS content theme (default: theme.css)")
    p.add_argument("--cover",        help=f"Cover style name or path (default: {DEFAULT_COVER}). Available: {', '.join(list_covers()) or 'none'}")
    p.add_argument("--list-covers",  action="store_true", help="List available cover styles and exit")
    p.add_argument("--no-cover",     action="store_true")
    p.add_argument("--no-cache",     action="store_true")
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