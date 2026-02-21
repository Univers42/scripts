/**
 * md-to-pdf.mjs — Markdown + Mermaid → Professional Styled PDF (Puppeteer)
 *
 * Uses headless Chromium to:
 *   1. Parse Markdown → HTML (via marked)
 *   2. Render Mermaid diagrams client-side (full Mermaid JS library)
 *   3. Print to PDF with precise A4 margins, header/footer
 *
 * TOC FIX: slugify() is defined ONCE and used in BOTH buildToc() (for href="#…")
 * AND the custom heading renderer (for id="…"), guaranteeing they always match.
 *
 * Usage:
 *   node md-to-pdf.mjs README.md
 *   node md-to-pdf.mjs README.md output.pdf
 *   node md-to-pdf.mjs README.md --title "My Doc" --author "Dev Team"
 *   node md-to-pdf.mjs README.md --no-cover
 *   node md-to-pdf.mjs README.md --debug-html
 */

import { readFile, writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── CLI ────────────────────────────────────────────────────────────────────
const args      = process.argv.slice(2);
const getFlag   = n => { const i = args.indexOf(n); return i === -1 ? null : (args[i+1] ?? true); };
const hasFlag   = n => args.includes(n);
const positional = args.filter((a,i) => !a.startsWith('--') && !args[i-1]?.startsWith('--'));

const inputPath        = positional[0] ? resolve(positional[0]) : null;
const outputPath       = resolve(positional[1] ?? (inputPath?.replace(/\.md$/i, '.pdf') ?? 'output.pdf'));
const titleOverride    = getFlag('--title');
const subtitleOverride = getFlag('--subtitle');
const authorOverride   = getFlag('--author');
const noCover          = hasFlag('--no-cover');
const debugHtml        = hasFlag('--debug-html');

if (!inputPath || !existsSync(inputPath)) {
  console.error('Usage: node md-to-pdf.mjs <input.md> [output.pdf] [--title "…"] [--author "…"] [--no-cover]');
  process.exit(1);
}

console.log(`\n📄  Input  : ${inputPath}`);
console.log(`📦  Output : ${outputPath}\n`);

// ── Read & detect metadata ─────────────────────────────────────────────────
const md = await readFile(inputPath, 'utf-8');

const today    = new Date().toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' });
const title    = titleOverride    || md.match(/^# (.+)$/m)?.[1]?.trim() || 'Document';
const subtitle = subtitleOverride || md.match(/^>\s*\*(.+)\*$/m)?.[1]?.trim() || '';
const author   = authorOverride   || '';

console.log(`📌  Title    : ${title}`);
console.log(`   Subtitle : ${subtitle || '(none)'}`);
console.log(`   Author   : ${author   || '(none)'}`);

// ── SHARED slugify ─────────────────────────────────────────────────────────
// THIS IS THE KEY FIX: one function used for both TOC hrefs AND heading ids.
function slugify(str) {
  return String(str)
    .toLowerCase()
    .replace(/<[^>]+>/g, '')          // strip HTML tags
    .replace(/[`*_[\]()#~]/g, '')     // strip markdown chars
    .replace(/&[a-z]+;/gi, '')        // strip HTML entities
    .replace(/[^\w\s-]/g, '')         // keep word chars, spaces, hyphens
    .trim()
    .replace(/[\s_]+/g, '-')          // spaces → hyphens
    .replace(/-+/g, '-')              // collapse multiple hyphens
    .replace(/^-|-$/g, '');           // trim leading/trailing hyphens
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;');
}

// ── TOC ────────────────────────────────────────────────────────────────────
function buildToc(text) {
  const items = [];
  for (const line of text.split('\n')) {
    const m2 = line.match(/^## (.+)$/);
    const m3 = line.match(/^### (.+)$/);
    if (m2) {
      const t = m2[1].trim();
      if (/table of contents/i.test(t)) continue;
      items.push({ level: 2, title: t, slug: slugify(t) });
    } else if (m3) {
      const t = m3[1].trim();
      items.push({ level: 3, title: t, slug: slugify(t) });
    }
  }
  if (!items.length) return '';

  let html = '<nav class="toc" aria-label="Table of Contents">\n'
           + '  <h2 class="toc-title">Table of Contents</h2>\n'
           + '  <ol class="toc-list">\n';

  let openH3 = false;
  for (const { level, title, slug } of items) {
    if (level === 2) {
      if (openH3) { html += '      </ol></li>\n'; openH3 = false; }
      html += `    <li class="toc-h2"><a href="#${slug}">${title}</a>\n`;
      openH3 = false;
    } else {
      if (!openH3) { html += '      <ol class="toc-sub">\n'; openH3 = true; }
      html += `        <li class="toc-h3"><a href="#${slug}">${title}</a></li>\n`;
    }
  }
  if (openH3) html += '      </ol></li>\n';
  else html += '    </li>\n';

  return html + '  </ol>\n</nav>\n';
}

// ── Marked renderer ────────────────────────────────────────────────────────
const { marked } = await import('marked');

// Track used slugs to handle duplicates
const usedSlugs = new Map();
function uniqueSlug(base) {
  const count = usedSlugs.get(base) ?? 0;
  usedSlugs.set(base, count + 1);
  return count === 0 ? base : `${base}-${count}`;
}

const renderer = new marked.Renderer();

// Headings — attach id using the SAME slugify() used in buildToc
renderer.heading = function(token) {
  const text  = typeof token === 'object' ? token.text  : token;
  const depth = typeof token === 'object' ? token.depth : arguments[1];
  const rawText = typeof token === 'object' ? (token.raw?.replace(/^#+\s*/, '').replace(/\n$/, '') ?? text) : text;
  const slug = uniqueSlug(slugify(rawText));
  return `<h${depth} id="${slug}">${text}</h${depth}>\n`;
};

renderer.code = function(token) {
  const code = typeof token === 'object' ? (token.text ?? '') : (token ?? '');
  const lang = (typeof token === 'object' ? (token.lang ?? '') : '').split(/[\s{]/)[0];
  if (lang === 'mermaid') {
    return `<div class="mermaid-wrap"><pre class="mermaid">${code}</pre></div>\n`;
  }
  return `<pre class="code-block"><code class="language-${lang}">${escapeHtml(code)}</code></pre>\n`;
};

marked.setOptions({ gfm: true, breaks: false });

// Strip existing manual TOC sections
const mdClean = md
  .replace(/^## Table of Contents\n[\s\S]*?(?=\n## |\n---)/m, '')
  .replace(/^## Table des matières\n[\s\S]*?(?=\n## |\n---)/m, '');

const toc     = buildToc(md);
const htmlBody = marked.parse(mdClean, { renderer });

// ── Cover page ─────────────────────────────────────────────────────────────
function buildCover(title, subtitle, author, today) {
  if (noCover) return '';
  const [mainTitle, ...rest] = title.split(/\s[—–:]\s/);
  const accentTitle = rest.length ? ` <span class="cover-accent">— ${rest.join(' — ')}</span>` : '';

  const metaRows = [
    author ? `<div class="meta-row"><span class="meta-label">Author</span><span class="meta-val">${author}</span></div>` : '',
    `<div class="meta-row"><span class="meta-label">Date</span><span class="meta-val">${today}</span></div>`,
    `<div class="meta-row"><span class="meta-label">Type</span><span class="meta-val">Documentation</span></div>`,
  ].filter(Boolean).join('\n    ');

  return `
<div class="cover">
  <div class="cover-stripe"></div>
  <div class="cover-content">
    <div class="cover-eyebrow">Technical Document</div>
    <h1 class="cover-title">${mainTitle}${accentTitle}</h1>
    ${subtitle ? `<p class="cover-subtitle">${subtitle}</p>` : ''}
    <div class="cover-rule"></div>
    <div class="cover-meta">
      ${metaRows}
    </div>
  </div>
  <div class="cover-footer">
    <span class="cover-footer-text">Confidential · For internal use only</span>
  </div>
</div>`;
}

// ── Full HTML ──────────────────────────────────────────────────────────────
const htmlTitle = escapeHtml(title);

const fullHtml = /* html */`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>${htmlTitle}</title>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<style>
/* ═══════════════════════════════════════════════════════════════════
   PROFESSIONAL PDF STYLESHEET  ·  md-to-pdf v2
   Palette:
     Primary   #0f62fe  (IBM Blue)
     Surface   #ffffff / #f4f4f4
     Text      #161616 / #525252
     Accent    #0353e9 dark blue
     Warning   #f1c21b  gold
   ═══════════════════════════════════════════════════════════════════ */

:root {
  --blue:        #0f62fe;
  --blue-dark:   #0353e9;
  --blue-mid:    #4589ff;
  --blue-light:  #edf4ff;
  --gold:        #f1c21b;
  --navy:        #071d3f;
  --charcoal:    #161616;
  --text:        #161616;
  --text-2:      #393939;
  --text-3:      #525252;
  --text-4:      #6f6f6f;
  --border:      #e0e0e0;
  --border-2:    #c6c6c6;
  --surface-1:   #f4f4f4;
  --surface-2:   #ffffff;
  --green:       #24a148;
  --purple:      #8a3ffc;
  --red:         #da1e28;
}

/* ── Reset ─────────────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
html { font-size: 13px; }
body {
  font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
  color: var(--text);
  line-height: 1.7;
  background: #fff;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}

/* ══════════════════════════════════════════════════
   COVER PAGE
   ══════════════════════════════════════════════════ */
.cover {
  width: 100%;
  min-height: 100vh;
  background: var(--navy);
  display: flex;
  flex-direction: column;
  position: relative;
  page-break-after: always;
  margin: 0 -18mm;
  padding: 0;
  overflow: hidden;
}

/* Diagonal accent band */
.cover::before {
  content: '';
  position: absolute;
  bottom: -80px;
  right: -80px;
  width: 380px;
  height: 380px;
  background: var(--blue);
  opacity: 0.18;
  border-radius: 50%;
}
.cover::after {
  content: '';
  position: absolute;
  top: -100px;
  right: 40px;
  width: 260px;
  height: 260px;
  background: var(--blue-mid);
  opacity: 0.12;
  border-radius: 50%;
}

.cover-stripe {
  height: 5px;
  background: linear-gradient(90deg, var(--blue) 0%, var(--blue-mid) 60%, var(--gold) 100%);
  flex-shrink: 0;
}

.cover-content {
  flex: 1;
  padding: 48px 44px 40px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  position: relative;
  z-index: 1;
}

.cover-eyebrow {
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.22em;
  text-transform: uppercase;
  color: var(--gold);
  margin-bottom: 20px;
}

.cover-title {
  font-size: 36px;
  font-weight: 800;
  line-height: 1.1;
  color: #ffffff;
  margin-bottom: 16px;
  border: none;
  padding: 0;
}

.cover-accent { color: var(--blue-mid); }

.cover-subtitle {
  font-size: 13px;
  color: #8d8d8d;
  line-height: 1.55;
  max-width: 380px;
  font-style: italic;
  margin-bottom: 36px;
}

.cover-rule {
  width: 40px;
  height: 3px;
  background: var(--blue);
  margin-bottom: 28px;
}

.cover-meta {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.meta-row {
  display: flex;
  align-items: baseline;
  gap: 0;
}

.meta-label {
  font-size: 8px;
  text-transform: uppercase;
  letter-spacing: 0.14em;
  color: #6f6f6f;
  width: 80px;
  flex-shrink: 0;
}

.meta-val {
  font-size: 10.5px;
  font-weight: 600;
  color: #c6c6c6;
}

.cover-footer {
  padding: 14px 44px;
  border-top: 1px solid rgba(255,255,255,0.07);
  position: relative;
  z-index: 1;
}

.cover-footer-text {
  font-size: 8px;
  color: #525252;
  text-transform: uppercase;
  letter-spacing: 0.1em;
}

/* ══════════════════════════════════════════════════
   TABLE OF CONTENTS
   ══════════════════════════════════════════════════ */
.toc {
  page-break-after: always;
  padding: 6px 0 20px;
}

.toc-title {
  font-size: 18px;
  font-weight: 800;
  color: var(--charcoal);
  padding: 0 0 12px 0 !important;
  margin: 0 0 4px 0 !important;
  border: none !important;
  border-bottom: 3px solid var(--blue) !important;
  background: transparent !important;
  letter-spacing: -0.01em;
}

.toc-list {
  list-style: none;
  padding: 0;
  margin: 8px 0 0;
  counter-reset: toc-h2;
}

.toc-list > li {
  counter-increment: toc-h2;
  padding: 0;
}

.toc-h2 {
  display: block;
  padding: 8px 0 4px;
  border-bottom: 1px solid var(--border);
}

.toc-h2 > a {
  display: flex;
  align-items: baseline;
  gap: 10px;
  text-decoration: none;
  font-size: 12px;
  font-weight: 600;
  color: var(--text);
  transition: color 0.1s;
}

.toc-h2 > a::before {
  content: counter(toc-h2, decimal-leading-zero);
  font-size: 9px;
  font-weight: 700;
  color: var(--blue);
  min-width: 22px;
  letter-spacing: 0.03em;
}

.toc-h2 > a::after {
  content: '';
  flex: 1;
  border-bottom: 1px dotted var(--border-2);
  margin: 0 6px;
  position: relative;
  top: -2px;
}

.toc-sub {
  list-style: none;
  padding: 2px 0 6px 32px;
  margin: 0;
  counter-reset: toc-h3;
}

.toc-h3 {
  counter-increment: toc-h3;
  padding: 3px 0;
}

.toc-h3 > a {
  font-size: 10.5px;
  font-weight: 400;
  color: var(--text-3);
  text-decoration: none;
}

/* ══════════════════════════════════════════════════
   TYPOGRAPHY  — Headings
   ══════════════════════════════════════════════════ */
h1 {
  font-size: 22px;
  font-weight: 800;
  color: var(--charcoal);
  line-height: 1.2;
  margin: 48px 0 16px;
  padding-bottom: 10px;
  border-bottom: 2px solid var(--blue);
  letter-spacing: -0.02em;
  page-break-after: avoid;
}

h2 {
  font-size: 15px;
  font-weight: 700;
  color: var(--text);
  margin: 36px 0 12px;
  padding: 11px 14px 11px 16px;
  background: var(--surface-1);
  border-left: 4px solid var(--blue);
  border-radius: 0 4px 4px 0;
  line-height: 1.3;
  page-break-after: avoid;
}

h3 {
  font-size: 12.5px;
  font-weight: 700;
  color: var(--text-2);
  margin: 28px 0 10px;
  padding-bottom: 6px;
  border-bottom: 1px solid var(--border);
  letter-spacing: 0.01em;
  page-break-after: avoid;
}

h4 {
  font-size: 11.5px;
  font-weight: 700;
  color: var(--blue-dark);
  margin: 20px 0 8px;
  display: flex;
  align-items: center;
  gap: 8px;
  page-break-after: avoid;
}

h4::before {
  content: '◆';
  font-size: 7px;
  color: var(--blue);
}

h5 {
  font-size: 10px;
  font-weight: 700;
  color: var(--text-4);
  text-transform: uppercase;
  letter-spacing: 0.1em;
  margin: 16px 0 6px;
  page-break-after: avoid;
}

h6 {
  font-size: 10px;
  font-weight: 600;
  color: var(--text-4);
  margin: 12px 0 4px;
}

/* ══════════════════════════════════════════════════
   PROSE
   ══════════════════════════════════════════════════ */
p {
  margin: 0 0 10px;
  color: var(--text-2);
}

strong { color: var(--charcoal); font-weight: 700; }
em     { color: var(--text-3); font-style: italic; }
a      { color: var(--blue-dark); text-decoration: none; border-bottom: 1px solid var(--blue-mid); }

/* ══════════════════════════════════════════════════
   BLOCKQUOTES
   ══════════════════════════════════════════════════ */
blockquote {
  position: relative;
  margin: 16px 0;
  padding: 12px 18px 12px 20px;
  background: var(--blue-light);
  border-left: 3px solid var(--blue);
  border-radius: 0 6px 6px 0;
  color: var(--navy);
  font-size: 12px;
  page-break-inside: avoid;
}

blockquote p { margin: 2px 0; color: inherit; }

blockquote::before {
  content: '“';
  position: absolute;
  top: 2px;
  right: 12px;
  font-size: 42px;
  color: var(--blue-mid);
  opacity: 0.25;
  font-family: Georgia, serif;
  line-height: 1;
}

/* ══════════════════════════════════════════════════
   TABLES
   ══════════════════════════════════════════════════ */
.table-wrap {
  overflow: hidden;
  border-radius: 6px;
  border: 1px solid var(--border);
  margin: 18px 0 22px;
  page-break-inside: avoid;
}

table {
  width: 100%;
  border-collapse: collapse;
  font-size: 11px;
}

thead tr {
  background: var(--charcoal);
}

thead th {
  padding: 10px 13px;
  font-size: 9.5px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: #f4f4f4;
  text-align: left;
  border-right: 1px solid rgba(255,255,255,0.06);
}

thead th:last-child { border-right: none; }

tbody tr { border-bottom: 1px solid var(--border); }
tbody tr:last-child { border-bottom: none; }
tbody tr:nth-child(even) { background: var(--surface-1); }

tbody td {
  padding: 8px 13px;
  color: var(--text-2);
  vertical-align: top;
  line-height: 1.5;
  border-right: 1px solid var(--border);
}

tbody td:last-child { border-right: none; }
tbody td:first-child { font-weight: 600; color: var(--charcoal); }

/* ══════════════════════════════════════════════════
   CODE
   ══════════════════════════════════════════════════ */
code {
  font-family: "Cascadia Code", "Fira Code", "Consolas", "Monaco", monospace;
  font-size: 0.85em;
  background: #ede9fe;
  color: #5b21b6;
  padding: 2px 6px;
  border-radius: 3px;
  border: 1px solid #ddd6fe;
  white-space: nowrap;
}

.code-block {
  background: #1e1e2e;
  color: #cdd6f4;
  padding: 16px 18px;
  border-radius: 8px;
  font-size: 10.5px;
  line-height: 1.65;
  margin: 12px 0 16px;
  overflow-x: auto;
  page-break-inside: avoid;
  white-space: pre-wrap;
  word-break: break-all;
  border: 1px solid #313244;
  position: relative;
}

.code-block::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 3px;
  background: linear-gradient(90deg, var(--blue) 0%, var(--purple) 100%);
  border-radius: 8px 8px 0 0;
}

.code-block code {
  background: none;
  border: none;
  padding: 0;
  color: inherit;
  font-size: inherit;
  white-space: inherit;
}

/* ══════════════════════════════════════════════════
   MERMAID DIAGRAMS
   ══════════════════════════════════════════════════ */
.mermaid-wrap {
  background: #fafbff;
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 20px;
  margin: 16px 0 20px;
  text-align: center;
  page-break-inside: avoid;
  position: relative;
}

.mermaid-wrap::before {
  content: 'Diagram';
  position: absolute;
  top: 8px;
  right: 12px;
  font-size: 8px;
  font-weight: 700;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--border-2);
}

pre.mermaid {
  margin: 0;
  padding: 0;
  border: none;
  background: transparent;
}

pre.mermaid svg {
  max-width: 100%;
  height: auto;
}

/* ══════════════════════════════════════════════════
   LISTS
   ══════════════════════════════════════════════════ */
ul, ol {
  padding-left: 22px;
  margin: 8px 0 12px;
  color: var(--text-2);
}

li { margin-bottom: 5px; line-height: 1.65; }

ul li::marker { color: var(--blue); }
ol li::marker { color: var(--blue); font-weight: 700; font-size: 0.9em; }

li > p { margin: 2px 0; }

/* Nested lists */
ul ul, ol ol, ul ol, ol ul { margin: 4px 0 4px; }

/* ══════════════════════════════════════════════════
   HR
   ══════════════════════════════════════════════════ */
hr {
  border: none;
  height: 1px;
  background: linear-gradient(90deg, var(--blue) 0%, var(--border) 60%, transparent 100%);
  margin: 28px 0;
}

/* ══════════════════════════════════════════════════
   IMAGES
   ══════════════════════════════════════════════════ */
img {
  max-width: 100%;
  border-radius: 6px;
  display: block;
  margin: 12px auto;
}

/* ══════════════════════════════════════════════════
   PRINT — page break rules
   ══════════════════════════════════════════════════ */
@media print {
  h1, h2, h3, h4, h5 { page-break-after: avoid; }
  .code-block, blockquote, .mermaid-wrap { page-break-inside: avoid; }
  .table-wrap { page-break-inside: auto; }
  tr { page-break-inside: avoid; }
}
</style>
</head>
<body>

${buildCover(title, subtitle, author, today)}

${toc}

${htmlBody}

<script>
mermaid.initialize({
  startOnLoad: true,
  theme: 'base',
  themeVariables: {
    primaryColor:          '#edf4ff',
    primaryBorderColor:    '#0f62fe',
    primaryTextColor:      '#161616',
    lineColor:             '#0f62fe',
    secondaryColor:        '#f4f4f4',
    tertiaryColor:         '#fafbff',
    fontFamily:            '"Segoe UI","Helvetica Neue",Arial,sans-serif',
    fontSize:              '12px',
    nodeBorder:            '#0f62fe',
    clusterBkg:            '#f4f4f4',
    clusterBorder:         '#a8c7ff',
    titleColor:            '#071d3f',
    edgeLabelBackground:   '#ffffff',
    activeTaskBkgColor:    '#0f62fe',
    activeTaskBorderColor: '#0353e9',
    critBkgColor:          '#da1e28',
    critBorderColor:       '#a2191f',
    doneTaskBkgColor:      '#24a148',
    taskTextColor:         '#ffffff',
    sectionBkgColor:       '#edf4ff',
    altSectionBkgColor:    '#f4f4f4',
  },
  flowchart:  { useMaxWidth: true, htmlLabels: true, curve: 'basis' },
  sequence:   { useMaxWidth: true, wrap: true, mirrorActors: false, boxMargin: 8 },
  er:         { useMaxWidth: true },
  gitGraph:   { useMaxWidth: true },
  pie:        { useMaxWidth: true },
  gantt:      { useMaxWidth: true, barHeight: 20, barGap: 4 },
});

// Wrap tables in a scrollable div for better overflow handling
document.querySelectorAll('table').forEach(t => {
  const wrap = document.createElement('div');
  wrap.className = 'table-wrap';
  t.parentNode.insertBefore(wrap, t);
  wrap.appendChild(t);
});
</script>
</body>
</html>`;

// ── Write debug HTML if requested ──────────────────────────────────────────
if (debugHtml) {
  const htmlPath = outputPath.replace(/\.pdf$/i, '.html');
  await writeFile(htmlPath, fullHtml, 'utf-8');
  console.log(`🔍  Debug HTML → ${htmlPath}`);
}

// ── Launch Puppeteer ───────────────────────────────────────────────────────
console.log('\n🚀  Launching headless browser…');
const puppeteer = await import('puppeteer');
const browser   = await puppeteer.default.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--font-render-hinting=none'],
});

const page = await browser.newPage();
page.on('console', msg => { if (msg.type() === 'error') console.warn(`  Browser: ${msg.text()}`); });

console.log('📝  Loading content…');
await page.setContent(fullHtml, { waitUntil: 'networkidle0', timeout: 60_000 });

console.log('🎨  Waiting for Mermaid…');
await page.waitForFunction(
  () => {
    const nodes = document.querySelectorAll('pre.mermaid');
    if (!nodes.length) return true;
    return [...nodes].every(n => n.querySelector('svg') || n.getAttribute('data-processed'));
  },
  { timeout: 30_000 }
).catch(() => console.warn('⚠  Some Mermaid diagrams may not have rendered.'));

await new Promise(r => setTimeout(r, 2_000));

console.log('🖨  Generating PDF…');
await page.pdf({
  path: outputPath,
  format: 'A4',
  printBackground: true,
  margin: { top: '22mm', bottom: '24mm', left: '18mm', right: '18mm' },
  displayHeaderFooter: true,
  headerTemplate: `
    <div style="font-size:7.5px;color:#8d8d8d;width:100%;display:flex;justify-content:space-between;
                padding:0 18mm;font-family:'Segoe UI',Arial,sans-serif;align-items:center;">
      <span style="color:#0f62fe;font-weight:700;letter-spacing:0.05em;text-transform:uppercase;font-size:6.5px;">
        ${escapeHtml(title)}
      </span>
      <span style="color:#c6c6c6;">Confidential</span>
    </div>`,
  footerTemplate: `
    <div style="font-size:7.5px;color:#8d8d8d;width:100%;display:flex;justify-content:space-between;
                padding:0 18mm;font-family:'Segoe UI',Arial,sans-serif;align-items:center;">
      <span style="color:#c6c6c6;">${escapeHtml(today)}</span>
      <span>Page <span class="pageNumber" style="color:#0f62fe;font-weight:700;"></span>
            <span style="color:#c6c6c6;"> / </span>
            <span class="totalPages" style="color:#8d8d8d;"></span></span>
    </div>`,
});

await browser.close();

const { statSync } = await import('node:fs');
const kb = Math.round(statSync(outputPath).size / 1024);
console.log(`\n✅  Done → ${outputPath}  (${kb} KB)\n`);
