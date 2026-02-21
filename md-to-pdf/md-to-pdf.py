#!/usr/bin/env python3
"""
md-to-pdf.py  —  Generic Markdown + Mermaid → Professional PDF
Uses Kroki.io (server-side PNG render) + WeasyPrint.

Usage:
  python3 md-to-pdf.py README.md
  python3 md-to-pdf.py README.md output.pdf
  python3 md-to-pdf.py README.md --title "Prismatica" --author "Dev Team" --subtitle "Project Brief"
  python3 md-to-pdf.py README.md --no-cover      # Skip cover page
  python3 md-to-pdf.py README.md --no-cache      # Force re-render all diagrams
"""

import sys, re, base64, hashlib, os, time, zlib, argparse
from pathlib import Path
from datetime import date

import requests
import markdown
from weasyprint import HTML


# ── Config ───────────────────────────────────────────────────────────────────
KROKI   = "https://kroki.io"
CACHE   = Path(__file__).parent / ".mermaid-cache"
TIMEOUT = 60
DELAY   = 1.2


# ── Mermaid → Kroki PNG ───────────────────────────────────────────────────────
def render_diagram(code: str, no_cache: bool = False) -> str | None:
    """Render a Mermaid diagram via Kroki.io and return a base64 PNG string."""
    CACHE.mkdir(exist_ok=True)
    h = hashlib.sha256(code.encode()).hexdigest()[:16]
    png_path = CACHE / f"{h}.png"

    if not no_cache and png_path.exists() and png_path.stat().st_size > 500:
        print(f"   ♻  Cache hit: {h}")
        return base64.b64encode(png_path.read_bytes()).decode()

    print(f"   🎨  Rendering via Kroki ({len(code)} chars)…")
    png_bytes = None

    # Try GET for small diagrams first (faster)
    if len(code) <= 2000:
        for attempt in range(2):
            try:
                encoded = base64.urlsafe_b64encode(
                    zlib.compress(code.encode("utf-8"), 9)
                ).decode("ascii")
                r = requests.get(f"{KROKI}/mermaid/png/{encoded}", timeout=TIMEOUT)
                r.raise_for_status()
                png_bytes = r.content
                print(f"   ✓  {len(png_bytes) // 1024} KB (GET)")
                break
            except Exception as e:
                print(f"   ⚠  GET attempt {attempt+1} failed: {e}")
                time.sleep(DELAY)

    # Fall back to POST
    if png_bytes is None:
        for attempt in range(3):
            try:
                time.sleep(DELAY)
                r = requests.post(
                    f"{KROKI}/mermaid/png",
                    json={"diagram_source": code},
                    headers={"Content-Type": "application/json"},
                    timeout=TIMEOUT,
                )
                r.raise_for_status()
                png_bytes = r.content
                print(f"   ✓  {len(png_bytes) // 1024} KB (POST)")
                break
            except Exception as e:
                print(f"   ⚠  POST attempt {attempt+1} failed: {e}")
                time.sleep(DELAY * (attempt + 1))

    if png_bytes:
        png_path.write_bytes(png_bytes)
        return base64.b64encode(png_bytes).decode()

    print("   ✗  All render attempts failed — using fallback code block")
    return None


def _strip_emojis(text: str) -> str:
    """Remove emoji characters (break Kroki rendering)."""
    return re.compile(
        "[\U0001F300-\U0001FAFF\U00002702-\U000027B0\U000024C2-\U0001F251"
        "\u2600-\u27BF\ufe0f\u200d]+", re.UNICODE
    ).sub("", text)


def replace_mermaid_blocks(md_text: str, no_cache: bool = False) -> str:
    """Replace ```mermaid fences with rendered PNG img tags."""
    n = [0]

    def _repl(m):
        n[0] += 1
        code = _strip_emojis(m.group(1).strip())
        print(f"\n   [{n[0]}] Diagram…")
        b64 = render_diagram(code, no_cache)
        if b64:
            return (
                f'\n<div class="diagram">'
                f'<img src="data:image/png;base64,{b64}" '
                f'alt="Diagram {n[0]}"/>'
                f'</div>\n'
            )
        esc = code.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        return (
            f'\n<div class="diagram-fallback">'
            f'<pre><code>{esc}</code></pre></div>\n'
        )

    return re.compile(r"```mermaid\s*\n(.*?)```", re.DOTALL).sub(_repl, md_text)


# ── Markdown pre-processors ───────────────────────────────────────────────────
def fix_blockquote_linebreaks(text: str) -> str:
    lines = text.split("\n")
    result = []
    in_code = False
    for i, line in enumerate(lines):
        stripped = line.rstrip()
        if stripped.startswith("```"):
            in_code = not in_code
        if not in_code and stripped.startswith(">"):
            next_bq = i + 1 < len(lines) and lines[i+1].rstrip().startswith(">")
            if next_bq and not stripped.endswith("  "):
                result.append(stripped + "  ")
                continue
        result.append(line)
    return "\n".join(result)


def fix_list_separation(text: str) -> str:
    lines = text.split("\n")
    result = []
    in_code = False
    for i, line in enumerate(lines):
        stripped = line.rstrip()
        if stripped.startswith("```"):
            in_code = not in_code
        if not in_code:
            is_list = bool(re.match(r"^\s*[-*]\s", stripped) or re.match(r"^\s*\d+\.\s", stripped))
            if is_list and i > 0:
                prev = lines[i-1].rstrip()
                prev_is_list = bool(re.match(r"^\s*[-*]\s", prev) or re.match(r"^\s*\d+\.\s", prev))
                if prev and not prev_is_list and not prev.startswith("#"):
                    result.append("")
        result.append(line)
    return "\n".join(result)


# ── Auto-detect metadata from Markdown ───────────────────────────────────────
def extract_title(md_text: str) -> str:
    """Extract the first H1 as the document title."""
    m = re.search(r"^# (.+)$", md_text, re.MULTILINE)
    return m.group(1).strip() if m else "Document"


def extract_subtitle(md_text: str) -> str:
    """Extract the first blockquote after H1 as a subtitle."""
    m = re.search(r"^> \*(.+)\*$", md_text, re.MULTILINE)
    if m:
        return m.group(1).strip()
    return ""


# ── TOC Builder ───────────────────────────────────────────────────────────────
def build_toc(md_text: str) -> str:
    lines = md_text.split("\n")
    items = []
    for line in lines:
        m2 = re.match(r"^## (.+)$", line)
        m3 = re.match(r"^### (.+)$", line)
        if m2:
            title = m2.group(1).strip()
            slug = re.sub(r"[^\w\s-]", "", title.lower())
            slug = re.sub(r"[\s]+", "-", slug).strip("-")
            items.append((2, title, slug))
        elif m3:
            title = m3.group(1).strip()
            slug = re.sub(r"[^\w\s-]", "", title.lower())
            slug = re.sub(r"[\s]+", "-", slug).strip("-")
            items.append((3, title, slug))
    if not items:
        return ""
    html = '<div class="toc">\n<h2 class="toc-title">Table of Contents</h2>\n'
    html += '<ul class="toc-list">\n'
    for level, title, slug in items:
        if "table of contents" in title.lower() or "table des matières" in title.lower():
            continue
        css = "toc-h2" if level == 2 else "toc-h3"
        html += f'  <li class="{css}"><a href="#{slug}">{title}</a></li>\n'
    html += '</ul>\n</div>\n'
    return html


# ── HTML Template ─────────────────────────────────────────────────────────────
def build_html_template(title: str, subtitle: str, author: str,
                         show_cover: bool, today: str) -> str:
    cover_html = ""
    if show_cover:
        # Split title on — or : for two-tone display
        parts = re.split(r"\s[—–:]\s", title, maxsplit=1)
        if len(parts) == 2:
            title_main = parts[0]
            title_accent = f' <span class="accent">— {parts[1]}</span>'
        else:
            title_main = title
            title_accent = ""

        safe_subtitle = subtitle.replace('"', '&quot;').replace('<', '&lt;').replace('>', '&gt;') if subtitle else ""
        cover_html = f"""
<div class="cover">
  <div class="cover-badge">Project Brief</div>
  <h1 class="cover-title">{title_main}{title_accent}</h1>
  {"<p class='cover-sub'>" + safe_subtitle + "</p>" if safe_subtitle else ""}
  <div class="cover-divider"></div>
  <div class="cover-meta">
    {"<div><span>Author</span><strong>" + author + "</strong></div>" if author else ""}
    <div><span>Date</span><strong>{today}</strong></div>
    <div><span>Classification</span><strong>Educational — Not for redistribution</strong></div>
  </div>
</div>
"""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>{title}</title>
<style>
/* ═══════════════════════════════════════════════════════════
   PRISMATICA — PDF Stylesheet
   Engine: WeasyPrint
   Palette: Indigo/Violet + Slate neutrals
   ═══════════════════════════════════════════════════════════ */

/* ── Font features ─────────────────────────────────────── */
@font-face {{
  font-family: "FallbackSans";
  src: local("Liberation Sans"), local("Noto Sans"), local("DejaVu Sans");
}}

/* ── Page setup ────────────────────────────────────────── */
@page {{
  size: A4;
  margin: 22mm 20mm 24mm 20mm;
  @bottom-center {{
    content: counter(page) " / " counter(pages);
    font-size: 7pt;
    color: #94a3b8;
    font-family: "Liberation Sans", sans-serif;
  }}
  @top-right {{
    content: "{title}";
    font-size: 6.5pt;
    color: #cbd5e1;
    font-family: "Liberation Sans", sans-serif;
  }}
}}
@page :first {{
  @bottom-center {{ content: none; }}
  @top-right {{ content: none; }}
}}

/* ── Reset ─────────────────────────────────────────────── */
*, *::before, *::after {{
  box-sizing: border-box;
  letter-spacing: 0 !important;
  word-spacing: normal !important;
  font-kerning: none;
}}
html, body {{ margin: 0; padding: 0; }}

/* ── Body ──────────────────────────────────────────────── */
body {{
  font-family: "Liberation Sans", "Noto Sans", sans-serif;
  font-size: 9.5pt;
  color: #1e293b;
  line-height: 1.75;
  overflow-wrap: break-word;
  font-variant-numeric: tabular-nums;
  -weasyprint-hyphens: none;
}}

/* ── COVER ─────────────────────────────────────────────── */
.cover {{
  page-break-after: always;
  min-height: 220mm;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: flex-start;
  padding: 0 10mm;
  background: linear-gradient(160deg, #0f172a 0%, #1e1b4b 60%, #0f172a 100%);
  color: #f1f5f9;
  margin: -22mm -20mm 0 -20mm;
  padding: 40mm 28mm 32mm;
}}
.cover-badge {{
  display: inline-block;
  background: #4f46e5;
  color: #fff;
  font-size: 7pt;
  font-weight: 700;
  letter-spacing: 0.12em !important;
  text-transform: uppercase;
  padding: 5px 14px;
  border-radius: 20px;
  margin-bottom: 22px;
}}
.cover-title {{
  font-size: 30pt;
  font-weight: 800;
  color: #f8fafc;
  line-height: 1.1;
  margin: 0 0 14px 0;
  padding: 0;
  border: none;
}}
.cover-title .accent {{ color: #818cf8; }}
.cover-sub {{
  font-size: 11pt;
  color: #94a3b8;
  margin: 0 0 28px 0;
  font-style: italic;
  max-width: 120mm;
  line-height: 1.5;
}}
.cover-divider {{
  width: 48px;
  height: 3px;
  background: #4f46e5;
  margin-bottom: 28px;
  border-radius: 2px;
}}
.cover-meta {{
  font-size: 9pt;
  color: #94a3b8;
  display: flex;
  flex-direction: column;
  gap: 6px;
}}
.cover-meta div {{
  display: flex;
  gap: 12px;
  align-items: baseline;
}}
.cover-meta span {{
  min-width: 90px;
  color: #64748b;
  font-size: 8pt;
  text-transform: uppercase;
  letter-spacing: 0.07em !important;
}}
.cover-meta strong {{
  color: #e2e8f0;
  font-weight: 600;
}}

/* ── TOC ───────────────────────────────────────────────── */
.toc {{
  page-break-after: always;
  padding-top: 8px;
}}
.toc-title {{
  font-size: 15pt;
  font-weight: 700;
  color: #0f172a;
  border-bottom: 2px solid #4f46e5;
  padding-bottom: 8px;
  margin-bottom: 16px;
  border-left: none;
  padding-left: 0;
  margin-top: 0;
}}
.toc-list {{
  list-style: none;
  padding: 0;
  margin: 0;
}}
.toc-list li {{
  padding: 4px 0 4px 0;
  border-bottom: 1px dotted #e2e8f0;
  line-height: 1.5;
}}
.toc-list li a {{
  color: #1e293b;
  text-decoration: none;
  font-size: 9.5pt;
}}
.toc-h2 {{ font-weight: 600; }}
.toc-h3 {{
  padding-left: 18px;
  font-weight: 400;
}}
.toc-h3 a {{ color: #64748b !important; font-size: 9pt !important; }}

/* ── HEADINGS ──────────────────────────────────────────── */
h1 {{
  font-size: 17pt;
  font-weight: 800;
  color: #0f172a;
  margin-top: 40px;
  margin-bottom: 14px;
  padding-bottom: 8px;
  border-bottom: 2px solid #4f46e5;
  page-break-after: avoid;
  overflow-wrap: break-word;
}}
h2 {{
  font-size: 13pt;
  font-weight: 700;
  color: #1e293b;
  margin-top: 32px;
  margin-bottom: 10px;
  padding: 9px 12px;
  background: #f8fafc;
  border-left: 4px solid #4f46e5;
  border-radius: 0 4px 4px 0;
  page-break-after: avoid;
  overflow-wrap: break-word;
}}
h3 {{
  font-size: 11pt;
  font-weight: 600;
  color: #334155;
  margin-top: 24px;
  margin-bottom: 8px;
  padding-bottom: 4px;
  border-bottom: 1px solid #e2e8f0;
  page-break-after: avoid;
}}
h4 {{
  font-size: 10pt;
  font-weight: 600;
  color: #4f46e5;
  margin-top: 16px;
  margin-bottom: 6px;
  page-break-after: avoid;
}}
h5 {{
  font-size: 9pt;
  font-weight: 700;
  color: #64748b;
  text-transform: uppercase;
  letter-spacing: 0.06em !important;
  margin-top: 12px;
  margin-bottom: 4px;
}}

/* ── PARAGRAPHS ────────────────────────────────────────── */
p {{
  margin-top: 0;
  margin-bottom: 9px;
  orphans: 3;
  widows: 3;
  overflow-wrap: break-word;
}}
strong {{ color: #0f172a; font-weight: 700; }}
em {{ color: #475569; }}

/* ── BLOCKQUOTE ────────────────────────────────────────── */
blockquote {{
  border-left: 3px solid #818cf8;
  background: #eef2ff;
  margin: 14px 0;
  padding: 10px 16px;
  font-size: 9pt;
  color: #312e81;
  border-radius: 0 6px 6px 0;
  page-break-inside: avoid;
}}
blockquote p {{ margin: 2px 0; }}

/* ── TABLES ────────────────────────────────────────────── */
table {{
  width: 100%;
  border-collapse: collapse;
  margin: 14px 0 18px;
  font-size: 8.5pt;
  table-layout: fixed;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  overflow: hidden;
}}
table td, table th {{ overflow-wrap: break-word; }}
thead th {{
  background: #0f172a;
  color: #f1f5f9;
  padding: 8px 11px;
  text-align: left;
  font-weight: 700;
  font-size: 8pt;
  letter-spacing: 0.03em;
  border-bottom: 2px solid #4f46e5;
}}
tbody td {{
  padding: 7px 11px;
  border-bottom: 1px solid #e2e8f0;
  vertical-align: top;
  line-height: 1.55;
  color: #334155;
}}
tbody tr:nth-child(even) {{ background: #f8fafc; }}
tbody td:first-child {{
  font-weight: 600;
  color: #1e293b;
}}

/* ── INLINE CODE ───────────────────────────────────────── */
code {{
  font-family: "Liberation Mono", "Courier New", monospace;
  font-size: 0.85em;
  background: #ede9fe;
  padding: 1px 5px;
  border-radius: 3px;
  color: #5b21b6;
  overflow-wrap: break-word;
}}

/* ── CODE BLOCKS ───────────────────────────────────────── */
pre {{
  background: #0f172a;
  color: #e2e8f0;
  padding: 14px 16px;
  border-radius: 8px;
  font-size: 7.5pt;
  line-height: 1.65;
  margin: 10px 0 14px;
  white-space: pre-wrap;
  overflow-wrap: break-word;
  page-break-inside: avoid;
  border: 1px solid #1e293b;
}}
pre code {{
  background: none;
  padding: 0;
  color: inherit;
  font-size: inherit;
}}

/* ── MERMAID DIAGRAMS ──────────────────────────────────── */
.diagram {{
  text-align: center;
  margin: 16px 0;
  padding: 14px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  page-break-inside: auto;
}}
.diagram img {{
  max-width: 100%;
  max-height: 680px;
  width: auto;
  height: auto;
  object-fit: contain;
}}
.diagram-fallback {{
  background: #fafafa;
  border: 1px dashed #cbd5e1;
  border-radius: 6px;
  padding: 10px;
  margin: 10px 0;
}}
.diagram-fallback pre {{
  background: #f1f5f9;
  color: #64748b;
  font-size: 7pt;
}}

/* ── LISTS ─────────────────────────────────────────────── */
ul, ol {{
  padding-left: 26px;
  margin: 8px 0 12px;
  color: #334155;
  overflow-wrap: break-word;
}}
ol {{ list-style-type: decimal; list-style-position: outside; }}
ul {{ list-style-type: disc; list-style-position: outside; }}
li {{
  margin-bottom: 4px;
  line-height: 1.65;
  overflow-wrap: break-word;
}}
li::marker {{ color: #4f46e5; font-weight: 700; }}
li > p {{ margin: 2px 0; }}

/* ── LINKS ─────────────────────────────────────────────── */
a {{ color: #4f46e5; text-decoration: none; }}

/* ── HR ────────────────────────────────────────────────── */
hr {{
  border: none;
  height: 1px;
  background: linear-gradient(to right, #4f46e5, transparent);
  margin: 22px 0;
}}

/* ── IMAGES ────────────────────────────────────────────── */
img {{ max-width: 100%; border-radius: 4px; }}

/* ── PAGE BREAKS ───────────────────────────────────────── */
h1, h2, h3, h4 {{ page-break-after: avoid; }}
pre {{ page-break-inside: avoid; }}
table {{ page-break-inside: auto; }}
tr {{ page-break-inside: avoid; }}
blockquote {{ page-break-inside: avoid; }}

</style>
</head>
<body>
{cover_html}
{{toc}}
{{body}}
</body>
</html>"""


# ── Main ──────────────────────────────────────────────────────────────────────
def convert(args):
    input_path  = args.input
    output_path = args.output or input_path.replace(".md", ".pdf")
    today       = date.today().strftime("%B %d, %Y")

    print(f"\n📄  Input  : {input_path}")
    print(f"📦  Output : {output_path}\n")

    md_text = Path(input_path).read_text(encoding="utf-8")
    print(f"📖  Read {len(md_text):,} characters")

    # Auto-detect metadata unless overridden
    title    = args.title    or extract_title(md_text)
    subtitle = args.subtitle or extract_subtitle(md_text)
    author   = args.author   or ""

    print(f"📌  Title    : {title}")
    print(f"   Subtitle : {subtitle or '(none)'}")
    print(f"   Author   : {author   or '(none)'}")

    # TOC before any transformation
    toc_html = build_toc(md_text)
    # Normalize repeated hyphens in TOC slugs to match heading ids
    toc_html = re.sub(r"-+", "-", toc_html)
    print(f"📑  TOC: {toc_html.count('<li')} entries")

    # Remove any existing manual TOC section
    md_text = re.sub(
        r"## Table of Contents\n([\s\S]*?)(?=\n---|$|\n## )",
        "", md_text, count=1
    )
    md_text = re.sub(
        r"## Table des matières\n([\s\S]*?)(?=\n---|$|\n## )",
        "", md_text, count=1
    )

    # Pre-processors
    md_text = fix_blockquote_linebreaks(md_text)
    md_text = fix_list_separation(md_text)

    # Clear cache if requested
    if args.no_cache and CACHE.exists():
        for f in CACHE.iterdir():
            f.unlink()
        print("🗑  Cleared diagram cache")

    # Render Mermaid diagrams
    count = len(re.findall(r"```mermaid", md_text))
    print(f"\n🎨  Found {count} Mermaid diagram(s) — rendering via Kroki…")
    md_text = replace_mermaid_blocks(md_text, args.no_cache)

    # Markdown → HTML
    print("\n📝  Converting Markdown → HTML…")
    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "sane_lists", "smarty", "attr_list"],
        output_format="html5",
    )

    # Ensure H2/H3 headings have id attributes that match the TOC slugs
    def slugify(text: str) -> str:
      s = re.sub(r"[^\w\s-]", "", text)
      s = s.strip().lower()
      s = re.sub(r"\s+", "-", s)
      return re.sub(r"(^-|-$)", "", s)

    def add_heading_ids(html: str) -> str:
      def repl(m):
        tag = m.group(1)
        inner = m.group(2)
        # strip inner HTML to produce slug base
        text_only = re.sub(r"<[^>]+>", "", inner).strip()
        if 'id="' in m.group(0):
          return m.group(0)
        sid = slugify(text_only)
        return f"<{tag} id=\"{sid}\">{inner}</{tag}>"
      return re.sub(r"<(h[2-3])>(.*?)</\1>", repl, html, flags=re.DOTALL)

    html_body = add_heading_ids(html_body)

    # Build full HTML
    template = build_html_template(title, subtitle, author,
                                   not args.no_cover, today)
    full_html = template.replace("{toc}", toc_html).replace("{body}", html_body)

    # Remap TOC hrefs to match generated ids (collapse repeated hyphens)
    ids = re.findall(r'id="([^"]+)"', full_html)
    idset = set(ids)
    def remap_href(m):
      h = m.group(1)
      if h in idset:
        return f'href="#{h}"'
      c = re.sub(r"-+", "-", h)
      if c in idset:
        return f'href="#{c}"'
      d = h.replace("--", "-")
      if d in idset:
        return f'href="#{d}"'
      return m.group(0)
    full_html = re.sub(r'href="([^"]+)"', remap_href, full_html)

    # Debug HTML
    html_path = output_path.replace(".pdf", ".html")
    Path(html_path).write_text(full_html, encoding="utf-8")
    print(f"🔍  Debug HTML → {html_path}")

    # Generate PDF
    print("\n🖨  Generating PDF with WeasyPrint…")
    HTML(string=full_html, base_url=str(Path(input_path).parent)).write_pdf(output_path)

    size_kb = os.path.getsize(output_path) / 1024
    print(f"\n✅  Done → {output_path}  ({size_kb:.0f} KB)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert a Markdown file (with Mermaid) to a styled PDF."
    )
    parser.add_argument("input",           help="Input .md file")
    parser.add_argument("output",          nargs="?", help="Output .pdf file (optional)")
    parser.add_argument("--title",         help="Override document title")
    parser.add_argument("--subtitle",      help="Override document subtitle")
    parser.add_argument("--author",        help="Author name for cover page")
    parser.add_argument("--no-cover",      action="store_true", help="Skip cover page")
    parser.add_argument("--no-cache",      action="store_true", help="Force re-render all diagrams")
    args = parser.parse_args()

    if not Path(args.input).exists():
        print(f"✗  File not found: {args.input}")
        sys.exit(1)

    convert(args)
