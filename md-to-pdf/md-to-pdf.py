#!/usr/bin/env python3
#!/usr/bin/env python3
"""
md-to-pdf.py  —  Markdown + Mermaid → Professional PDF  (WeasyPrint + Kroki)

ROOT-CAUSE TOC FIXES:
  1. slugify() is now defined ONCE and called for both build_toc() hrefs and
     add_heading_ids() id-attributes, guaranteeing they always match.
  2. The Python markdown library HTML-encodes '&' → '&amp;' in heading text.
     The old add_heading_ids slugify didn't strip HTML entities, so it produced
     "65-embed-amp-external-impact" while build_toc produced "65-embed-external-impact".
     Fixed by stripping HTML entities before slugifying in BOTH call sites.
  3. Em-dash (—) is explicitly converted to '-' before other processing.
  4. Cover extended to full physical page with matching negative margins.

Usage:
  python3 md-to-pdf.py README.md
  python3 md-to-pdf.py README.md out.pdf --title "My Doc" --author "Team" --no-cover
  python3 md-to-pdf.py README.md --no-cache   # force re-render Mermaid diagrams
"""

import sys, re, base64, hashlib, os, time, zlib, argparse
from pathlib import Path
from datetime import date
from collections import defaultdict

import requests
import markdown
from weasyprint import HTML


# ── Config ────────────────────────────────────────────────────────────────
KROKI_URL = "https://kroki.io"
CACHE_DIR = Path(__file__).parent / ".mermaid-cache"
TIMEOUT   = 60
DELAY     = 1.2


# ════════════════════════════════════════════════════════════════════════════
#  SHARED SLUGIFY — single definition, called everywhere
#  Input MUST be raw markdown text (never HTML-encoded text).
#  This ensures build_toc() hrefs and add_heading_ids() ids always match.
# ════════════════════════════════════════════════════════════════════════════
def slugify(text: str) -> str:
    s = re.sub(r"<[^>]+>", "", text)          # strip HTML tags
    s = s.replace("\u2014", "-").replace("\u2013", "-")  # em/en-dash → hyphen
    s = re.sub(r"&[a-zA-Z]+;", "", s)         # strip HTML entities (&amp; &lt; …)
    s = s.lower()
    s = re.sub(r"[\s_]+", "-", s)             # whitespace → hyphens
    s = re.sub(r"[^\w-]", "", s)              # keep only word chars + hyphens
    s = re.sub(r"-+", "-", s)                 # collapse repeated hyphens
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
            items.append((2, t, slugify(t)))  # slugify on RAW markdown text
        elif m3:
            t = m3.group(1)
            items.append((3, t, slugify(t)))

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
#  COVER HTML
# ════════════════════════════════════════════════════════════════════════════
def build_cover_html(title: str, subtitle: str, author: str, today: str) -> str:
    parts = re.split(r"\s[—–:]\s", title, maxsplit=1)
    # Using proper HTML encoding
    main = parts[0].replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
    accent_html = ""
    if len(parts) > 1:
        a = parts[1].replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
        accent_html = f'<span class="cover-title-accent">{a}</span>'
    
    sub_html = f'<p class="cover-sub">{subtitle}</p>' if subtitle else ""
    auth_html = (f'<div class="meta-row"><span class="meta-k">Author</span>'
                 f'<span class="meta-v">{author}</span></div>') if author else ""
    
    return f"""<div class="cover">
      
      <header class="cover-header">
        <div class="brand-logo">◆ 42 Transcendance</div>
        <div class="doc-badge">Tech Brief</div>
      </header>

      <div class="cover-stripe"></div>
      
      <div class="cover-body">
        <p class="cover-eyebrow">Project Documentation</p>
        <h1 class="cover-h1">{main}{accent_html}</h1>
        {sub_html}
        <div class="cover-rule"></div>
        <div class="cover-meta">
          {auth_html}
          <div class="meta-row"><span class="meta-k">Date</span><span class="meta-v">{today}</span></div>
          <div class="meta-row"><span class="meta-k">Status</span><span class="meta-v">Final Release</span></div>
        </div>
      </div>
      
      <div class="cover-foot">
        <span class="cover-foot-text">Confidential · Internal use only</span>
        <span class="cover-foot-dots">● ● ●</span>
      </div>
    </div>
"""


# ════════════════════════════════════════════════════════════════════════════
#  COMPLETE HTML DOCUMENT
# ════════════════════════════════════════════════════════════════════════════
_CSS = """
/*
 * PALETTE — Modern Editorial (Obsidian & Amber)
 */
:root {
  --ink: #111827;
  --mid: #374151;
  --muted: #6b7280;
  --surface: #f9fafb;
  --border: #e5e7eb;
  --accent: #c87533;
  --accent-light: #fbcfe8;
}

@font-face { font-family: BodySans; src: local("Liberation Sans"),local("Noto Sans"),local("DejaVu Sans"); }
@font-face { font-family: CodeMono; src: local("Liberation Mono"),local("Consolas"),local("Courier New"); }

/* ─── PAGE SETUP ───────────────────────────────────────── */
@page {
  size: A4;
  margin: 25mm 20mm 25mm 20mm;
  @bottom-center {
    content: counter(page) " / " counter(pages);
    font-size: 8pt;
    color: #9ca3af;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    letter-spacing: 0.05em;
  }
  @top-right {
    content: "DOC_TITLE";
    font-size: 7.5pt;
    color: #d1d5db;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    letter-spacing: 0.05em;
  }
}

/* 1. THE MAGIC FIX: Create a margin-less named page for the cover */
@page cover_page {
  margin: 0;
  @bottom-center { content: none; }
  @top-right { content: none; }
}

/* ─── RESET ────────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }

/* ─── BODY ─────────────────────────────────────────────── */
body {
  /* Modern UI font stack */
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  font-size: 10pt;
  color: var(--mid);
  line-height: 1.7;
  overflow-wrap: break-word;
  -weasyprint-hyphens: none;
  background: #ffffff;
}

/* ─── COVER ────────────────────────────────────────────── */
.cover {
  page: cover_page; 
  height: 297mm;
  width: 210mm;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  
  /* 1. The Base Gradient: Deep Obsidian to Slate */
  background: linear-gradient(135deg, #050b14 0%, #111827 50%, #0f172a 100%);
  color: #f5f1ea;
  margin: 0;
  padding: 0;
  position: relative;
}

/* 2. The Designer Touch: A subtle radial glow in the top right */
.cover::before {
  content: "";
  position: absolute;
  top: -20%;
  right: -20%;
  width: 80%;
  height: 80%;
  background: radial-gradient(circle, rgba(200,117,51,0.12) 0%, transparent 60%);
  z-index: 0;
  pointer-events: none;
}

/* 2b. Decorative halo / circle in the lower-left for depth */
.cover::after {
  content: "";
  position: absolute;
  left: -8%;
  bottom: -6%;
  width: 420px;
  height: 420px;
  background: radial-gradient(circle at 30% 30%, rgba(232,164,73,0.10) 0%, rgba(232,164,73,0.02) 40%, transparent 60%);
  border-radius: 50%;
  transform: rotate(8deg);
  z-index: 0;
  filter: blur(12px);
  pointer-events: none;
}

/* 2c. Faint dotted ring using multiple radial-gradients for subtle ornament */
.cover .decor-ring {
  position: absolute;
  right: 14%;
  top: 28%;
  width: 220px;
  height: 220px;
  z-index: 0;
  pointer-events: none;
  background:
    radial-gradient(circle at 50% 50%, rgba(232,164,73,0.06) 2%, transparent 2%),
    radial-gradient(circle at 50% 50%, rgba(232,164,73,0.03) 10%, transparent 10%);
  border-radius: 50%;
  filter: blur(6px);
}

/* Ensure all text sits above the background glow */
.cover > * {
  z-index: 1;
  position: relative;
}

/* 3. The New Header Layout */
.cover-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 40px 10% 20px; /* Aligns perfectly with the body padding */
  width: 100%;
}

.brand-logo {
  font-size: 11pt;
  font-weight: 800;
  letter-spacing: 0.2em;
  color: #e5e7eb;
}

.doc-badge {
  font-size: 7.5pt;
  font-weight: 700;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  background: rgba(200, 117, 51, 0.15);
  color: #e8a449;
  padding: 6px 12px;
  border-radius: 4px;
  border: 1px solid rgba(200, 117, 51, 0.25);
  backdrop-filter: blur(4px);
}

.cover-stripe {
  height: 4px;
  background: linear-gradient(90deg, #c87533 0%, #e8a449 55%, transparent 100%);
  flex-shrink: 0;
  margin: 0 10%; /* Inset the stripe to match the padding */
  border-radius: 2px;
  opacity: 0.8;
}

.cover-body {
  flex: 1;
  padding: 10%;
  display: flex;
  flex-direction: column;
  justify-content: center;
}

/* Keep your existing .cover-eyebrow, .cover-h1, etc. below this */
.cover-eyebrow {
  font-size: 8pt;
  font-weight: 700;
  letter-spacing: 0.25em;
  text-transform: uppercase;
  color: #e8a449;
  margin-bottom: 24px;
}

/* Restore original cover title, subtitle and meta styles */
.cover-h1, h1.cover-h1 {
  font-size: 30pt !important;
  font-weight: 800 !important;
  color: #f5f1ea !important;
  line-height: 1.12 !important;
  margin: 0 0 16px !important;
  padding: 0 !important;
  border: none !important;
  letter-spacing: -0.02em;
}
.cover-title-accent {
  display: block;
  margin-top: 6px;
  color: #e8a449;
  font-size: 0.7em;
  font-weight: 600;
}
.cover-sub {
  font-size: 11pt;
  color: #8c8782;
  font-style: italic;
  line-height: 1.6;
  margin-bottom: 34px;
}
.cover-rule {
  width: 36px;
  height: 2px;
  background: #c87533;
  margin-bottom: 26px;
}
.cover-meta { display: flex; flex-direction: column; gap: 10px; }
.meta-row   { display: flex; align-items: baseline; }
.meta-k {
  min-width: 72px;
  font-size: 7pt;
  font-weight: 700;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: #4a4540;
}
.meta-v { font-size: 10pt; font-weight: 500; color: #bfb9b0; }
.cover-foot {
  padding: 12px 48px;
  border-top: 1px solid rgba(255,255,255,0.10);
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: rgba(255,255,255,0.02);
}
.cover-foot-text {
  font-size: 7pt;
  letter-spacing: .12em;
  text-transform: uppercase;
  color: #f5f1ea;
  font-weight: 600;
}
.cover-foot-dots { font-size: 5pt; color: rgba(245,241,234,0.6); letter-spacing: 4px; opacity: .9; }

/* ─── TABLE OF CONTENTS ────────────────────────────────── */
.toc { page-break-after: always; padding-bottom: 20px; margin-top: 20px; }
h2.toc-title {
  font-size: 18pt !important;
  font-weight: 800 !important;
  color: var(--ink) !important;
  border: none !important;
  background: transparent !important;
  padding: 0 0 16px !important;
  margin: 0 0 12px !important;
  letter-spacing: -0.02em;
}
.toc-root { list-style: none; counter-reset: toc-h2; padding: 0; margin: 0; }
li.toc-h2 {
  counter-increment: toc-h2;
  border-bottom: 1px solid var(--border);
  padding: 0;
}
li.toc-h2 a {
  display: flex;
  align-items: baseline;
  gap: 12px;
  padding: 10px 0 8px;
  text-decoration: none;
  color: var(--ink);
  font-size: 10.5pt;
  font-weight: 600;
}
li.toc-h2 .toc-num::before {
  content: counter(toc-h2, decimal-leading-zero);
  font-size: 8.5pt;
  font-weight: 700;
  color: var(--accent);
  letter-spacing: .05em;
}
.toc-sub { list-style: none; padding: 4px 0 10px 32px; margin: 0; counter-reset: toc-h3; }
li.toc-h3 { counter-increment: toc-h3; padding: 4px 0; }
li.toc-h3 a { font-size: 9.5pt; color: var(--muted); text-decoration: none; transition: color 0.2s; }
li.toc-h3 a::before {
  content: counter(toc-h2) "." counter(toc-h3) " ";
  font-size: 8.5pt;
  color: #9ca3af;
  font-weight: 500;
  margin-right: 6px;
}

/* ─── HEADINGS (Modern & Clean) ────────────────────────── */
h1 {
  font-size: 22pt;
  font-weight: 800;
  color: var(--ink);
  margin: 48px 0 20px;
  padding-bottom: 12px;
  letter-spacing: -0.03em;
  page-break-after: avoid;
}

h2 {
  font-size: 16pt;
  font-weight: 700;
  color: var(--ink);
  margin: 40px 0 16px;
  padding-bottom: 8px;
  border-bottom: 2px solid var(--border);
  line-height: 1.3;
  letter-spacing: -0.02em;
  page-break-after: avoid;
}

h3 {
  font-size: 13pt;
  font-weight: 700;
  color: var(--ink);
  margin: 28px 0 12px;
  page-break-after: avoid;
}

h4 {
  font-size: 11pt;
  font-weight: 600;
  color: var(--accent);
  margin: 20px 0 8px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  page-break-after: avoid;
}

/* ─── PROSE & LINKS ────────────────────────────────────── */
p { margin: 0 0 12px; orphans: 3; widows: 3; }
strong { color: var(--ink); font-weight: 700; }
em { color: var(--muted); font-style: italic; }

a { 
  color: var(--ink); 
  font-weight: 500;
  text-decoration: underline; 
  text-decoration-color: var(--accent);
  text-decoration-thickness: 1.5px;
  text-underline-offset: 4px; /* Professional spacing for underlines */
}

/* ─── BLOCKQUOTES ──────────────────────────────────────── */
blockquote {
  margin: 20px 0;
  padding: 16px 20px;
  background: var(--surface);
  border-left: 4px solid var(--accent);
  border-radius: 0 6px 6px 0;
  font-size: 10.5pt;
  color: var(--mid);
  page-break-inside: avoid;
}
blockquote p { margin: 0; }

/* ─── TABLES ───────────────────────────────────────────── */
table {
  width: 100%;
  border-collapse: collapse;
  margin: 20px 0;
  font-size: 9pt;
  border: 1px solid var(--border);
  page-break-inside: auto;
  border-radius: 6px;
  overflow: hidden;
}
thead th {
  background: var(--surface);
  color: var(--ink);
  padding: 10px 14px;
  text-align: left;
  font-weight: 600;
  border-bottom: 2px solid var(--border);
}
tbody tr { border-bottom: 1px solid var(--border); }
tbody tr:nth-child(even) { background: #fafafa; }
tbody td { padding: 10px 14px; vertical-align: top; line-height: 1.5; }
tbody td:first-child { font-weight: 600; color: var(--ink); }

/* ─── CODE ─────────────────────────────────────────────── */
code {
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace;
  font-size: 0.85em;
  background: #f3f4f6;
  color: #b45309;
  padding: 3px 6px;
  border-radius: 4px;
}
pre {
  background: #111827;
  color: #e5e7eb;
  padding: 16px 20px;
  border-radius: 8px;
  font-size: 8.5pt;
  line-height: 1.6;
  margin: 16px 0;
  white-space: pre-wrap;
  page-break-inside: avoid;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
}
pre code { background: none; color: inherit; padding: 0; font-size: inherit; }

/* ─── LISTS & MISC ─────────────────────────────────────── */
ul, ol { padding-left: 24px; margin: 12px 0 16px; }
li { margin-bottom: 6px; }
li::marker { color: var(--accent); font-weight: 600; }
hr { border: none; height: 1px; background: var(--border); margin: 32px 0; }
img { max-width: 100%; border-radius: 6px; border: 1px solid var(--border); }

.diagram { text-align: center; margin: 24px 0; page-break-inside: avoid; }
.diagram img { max-width: 100%; max-height: 800px; border: none; }
"""


def build_html(
    title: str, subtitle: str, author: str,
    show_cover: bool, today: str,
    toc_html: str, body_html: str,
) -> str:
    safe_title  = title.replace('"', '&quot;').replace('<', '&lt;').replace('>', '&gt;')
    cover_html  = build_cover_html(title, subtitle, author, today) if show_cover else ""
    css         = _CSS.replace("DOC_TITLE", safe_title)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>{safe_title}</title>
<style>{css}</style>
</head>
<body>
{cover_html}
{toc_html}
{body_html}
</body>
</html>"""


# ════════════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════════════
def convert(args: argparse.Namespace) -> None:
    input_path  = args.input
    output_path = args.output or re.sub(r"\.md$", ".pdf", input_path)
    today       = date.today().strftime("%B %d, %Y")

    print(f"\n📄  Input  : {input_path}")
    print(f"📦  Output : {output_path}\n")

    md_text = Path(input_path).read_text(encoding="utf-8")
    print(f"📖  Read {len(md_text):,} chars")

    # Metadata
    title_match = re.search(r"^#\s+(.+)$", md_text, re.M)
    title       = args.title    or (title_match.group(1).strip() if title_match else "Document")
    sub_match   = re.search(r"^>\s*\*(.+)\*\s*$", md_text, re.M)
    subtitle    = args.subtitle or (sub_match.group(1).strip() if sub_match else "")
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

    full_html = build_html(title, subtitle, author, not args.no_cover, today, toc_html, body_html)

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
    p.add_argument("input")
    p.add_argument("output",       nargs="?")
    p.add_argument("--title",      help="Override document title")
    p.add_argument("--subtitle",   help="Override subtitle")
    p.add_argument("--author",     help="Author name for cover page")
    p.add_argument("--no-cover",   action="store_true")
    p.add_argument("--no-cache",   action="store_true")
    args = p.parse_args()

    if not Path(args.input).exists():
        print(f"✗  File not found: {args.input}")
        sys.exit(1)

    convert(args)