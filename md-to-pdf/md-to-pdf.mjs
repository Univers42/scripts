#!/usr/bin/env node
/**
 * md-to-pdf.mjs — Generic Markdown + Mermaid → Styled PDF (Puppeteer)
 *
 * This script uses a real headless Chromium browser to:
 *   1. Parse Markdown → HTML (via marked)
 *   2. Render Mermaid diagrams client-side with the full Mermaid JS library
 *   3. Print to PDF with precise A4 margins and header/footer
 *
 * Advantages over the Python version:
 *   - True Mermaid rendering (identical to browser output)
 *   - Supports all diagram types including gitGraph, timeline, etc.
 *   - No external API calls needed
 *
 * Usage:
 *   node md-to-pdf.mjs README.md
 *   node md-to-pdf.mjs README.md output.pdf
 *   node md-to-pdf.mjs README.md --title "Prismatica" --author "Dev Team"
 *   node md-to-pdf.mjs README.md --no-cover
 */

import { readFile, writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Parse CLI args ─────────────────────────────────────────────────────────
const args = process.argv.slice(2);

function getFlag(name) {
  const i = args.indexOf(name);
  if (i === -1) return null;
  return args[i + 1] ?? true;
}
function hasFlag(name) { return args.includes(name); }

const positional = args.filter(a => !a.startsWith('--') && !args[args.indexOf(a) - 1]?.startsWith('--'));
const inputPath  = positional[0] ? resolve(positional[0]) : null;
const outputPath = resolve(positional[1] ?? (inputPath?.replace(/\.md$/i, '.pdf') ?? 'output.pdf'));
const titleOverride    = getFlag('--title');
const subtitleOverride = getFlag('--subtitle');
const authorOverride   = getFlag('--author');
const noCover          = hasFlag('--no-cover');
const debugHtml        = hasFlag('--debug-html');

if (!inputPath || !existsSync(inputPath)) {
  console.error(`Usage: node md-to-pdf.mjs <input.md> [output.pdf] [--title "..."] [--author "..."] [--no-cover]`);
  process.exit(1);
}

console.log(`\n📄  Input  : ${inputPath}`);
console.log(`📦  Output : ${outputPath}\n`);

// ── Read Markdown ──────────────────────────────────────────────────────────
const md = await readFile(inputPath, 'utf-8');

// ── Auto-detect metadata ───────────────────────────────────────────────────
function extractTitle(text)    { return text.match(/^# (.+)$/m)?.[1]?.trim() ?? 'Document'; }
function extractSubtitle(text) { return text.match(/^> \*(.+)\*$/m)?.[1]?.trim() ?? ''; }

const today    = new Date().toLocaleDateString('en-GB', { day: '2-digit', month: 'long', year: 'numeric' });
const title    = titleOverride    || extractTitle(md);
const subtitle = subtitleOverride || extractSubtitle(md);
const author   = authorOverride   || '';

console.log(`📌  Title    : ${title}`);
console.log(`   Subtitle : ${subtitle || '(none)'}`);
console.log(`   Author   : ${author   || '(none)'}`);

// ── Parse Markdown → HTML ──────────────────────────────────────────────────
const { marked } = await import('marked');

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// Simple slugify used for TOC anchors and heading ids
function slugify(str) {
  return String(str)
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/^-|-$/g, '');
}

// Build TOC from ## and ### headings
function buildToc(text) {
  const items = [];
  for (const line of text.split('\n')) {
    const m2 = line.match(/^## (.+)$/);
    const m3 = line.match(/^### (.+)$/);
    if (m2) {
      const t = m2[1].trim();
      if (/table of contents/i.test(t)) continue;
      const slug = slugify(t);
      items.push({ level: 2, title: t, slug });
    } else if (m3) {
      const t = m3[1].trim();
      const slug = slugify(t);
      items.push({ level: 3, title: t, slug });
    }
  }
  if (!items.length) return '';
  let html = '<div class="toc"><h2 class="toc-title">Table of Contents</h2><ul class="toc-list">\n';
  for (const { level, title, slug } of items) {
    html += `  <li class="toc-h${level}"><a href="#${slug}">${title}</a></li>\n`;
  }
  return html + '</ul></div>\n';
}

// Remove any manual TOC from the markdown before parsing
let mdClean = md
  .replace(/## Table of Contents\n([\s\S]*?)(?=\n## |\n---|$)/m, '')
  .replace(/## Table des matières\n([\s\S]*?)(?=\n## |\n---|$)/m, '');

let toc = buildToc(md);
// Normalize repeated hyphens in generated slugs (avoid mismatches)
// Ensure hrefs inside the TOC use collapsed hyphens (match anchor ids)
toc = toc.replace(/href="#([^"]*)"/g, function(m, p1) {
  const clean = p1.replace(/-+/g, '-');
  return 'href="#' + clean + '"';
});

// Custom renderer
const renderer = new marked.Renderer();
renderer.code = function(token) {
  const code = typeof token === 'object' ? (token.text ?? '') : (token ?? '');
  const lang = typeof token === 'object' ? (token.lang ?? '') : '';

  if (lang === 'mermaid') {
    return `<div class="mermaid-wrap"><pre class="mermaid">${code}</pre></div>`;
  }
  return `<pre class="code-block"><code class="language-${lang}">${escapeHtml(code)}</code></pre>`;
};
// (No custom heading renderer — we'll add ids in a post-processing pass)

marked.setOptions({ gfm: true, breaks: false });
let htmlBody = marked.parse(mdClean, { renderer });

// ── Build cover HTML ───────────────────────────────────────────────────────
function buildCover(title, subtitle, author, today) {
  if (noCover) return '';
  const parts = title.split(/\s[—–:]\s/);
  const mainTitle  = parts[0];
  const accentPart = parts[1] ? ` <span class="accent">— ${parts[1]}</span>` : '';

  return `
<div class="cover">
  <div class="cover-inner">
    <div class="cover-badge">Project Brief</div>
    <h1 class="cover-title">${mainTitle}${accentPart}</h1>
    ${subtitle ? `<p class="cover-sub">${subtitle}</p>` : ''}
    <div class="cover-line"></div>
    <div class="cover-meta">
      ${author ? `<div class="cover-row"><span>Author</span><strong>${author}</strong></div>` : ''}
      <div class="cover-row"><span>Date</span><strong>${today}</strong></div>
      <div class="cover-row"><span>Type</span><strong>Educational — Not for redistribution</strong></div>
    </div>
  </div>
</div>`;
}

// ── Full HTML page ─────────────────────────────────────────────────────────
const fullHtml = /* html */`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>${title}</title>

<!-- Mermaid — loaded from CDN, rendered before PDF capture -->
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>

<style>
/* ═══════════════════════════════════════════════════════
   PRISMATICA — PDF Styles (Puppeteer / Chrome)
   Palette: Indigo-600 primary · Slate neutrals · Violet accents
   ═══════════════════════════════════════════════════════ */

/* ── Variables ──────────────────────────────────────── */
:root {
  --primary:     #4f46e5;
  --primary-dark:#3730a3;
  --violet:      #7c3aed;
  --bg-dark:     #0f172a;
  --bg-mid:      #1e293b;
  --text:        #1e293b;
  --text-muted:  #64748b;
  --border:      #e2e8f0;
  --bg-light:    #f8fafc;
  --code-bg:     #ede9fe;
  --code-color:  #5b21b6;
}

/* ── Base ───────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; }
html { font-size: 13px; }
body {
  font-family: "Segoe UI", Inter, system-ui, -apple-system, sans-serif;
  color: var(--text);
  line-height: 1.72;
  max-width: 100%;
  margin: 0; padding: 0;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}

/* ── COVER ──────────────────────────────────────────── */
.cover {
  width: 100vw;
  min-height: 100vh;
  background: linear-gradient(150deg, #0f172a 0%, #1e1b4b 55%, #0f172a 100%);
  display: flex;
  align-items: center;
  padding: 0;
  page-break-after: always;
  margin: 0 -18mm;
}
.cover-inner {
  padding: 32mm 28mm;
  width: 100%;
}
.cover-badge {
  display: inline-block;
  background: var(--primary);
  color: #fff;
  font-size: 8px;
  font-weight: 700;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  padding: 5px 16px;
  border-radius: 20px;
  margin-bottom: 24px;
}
.cover-title {
  font-size: 38px;
  font-weight: 800;
  color: #f8fafc;
  line-height: 1.1;
  margin: 0 0 16px 0;
  border: none;
  padding: 0;
}
.cover-title .accent { color: #a5b4fc; }
.cover-sub {
  font-size: 13px;
  color: #94a3b8;
  max-width: 420px;
  line-height: 1.6;
  font-style: italic;
  margin: 0 0 32px 0;
}
.cover-line {
  width: 52px;
  height: 3px;
  background: var(--primary);
  border-radius: 2px;
  margin-bottom: 28px;
}
.cover-meta {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.cover-row {
  display: flex;
  gap: 14px;
  align-items: baseline;
}
.cover-row span {
  min-width: 80px;
  font-size: 9px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: #475569;
}
.cover-row strong {
  font-size: 11px;
  font-weight: 600;
  color: #e2e8f0;
}

/* ── TOC ────────────────────────────────────────────── */
.toc {
  page-break-after: always;
  padding-top: 10px;
}
.toc-title {
  font-size: 20px;
  font-weight: 700;
  color: var(--bg-dark);
  border-bottom: 2px solid var(--primary) !important;
  border-left: none !important;
  padding: 0 0 8px 0 !important;
  background: transparent !important;
  margin-bottom: 16px;
}
.toc-list {
  list-style: none;
  padding: 0;
  margin: 0;
}
.toc-list li {
  padding: 5px 0;
  border-bottom: 1px dotted var(--border);
  line-height: 1.5;
}
.toc-list li a {
  text-decoration: none;
  font-size: 12px;
}
.toc-h2 { font-weight: 600; }
.toc-h2 a { color: var(--text); }
.toc-h3 { padding-left: 18px; }
.toc-h3 a { color: var(--text-muted); font-size: 11px; }

/* ── HEADINGS ───────────────────────────────────────── */
h1 {
  font-size: 22px;
  font-weight: 800;
  color: var(--bg-dark);
  border-bottom: 2px solid var(--primary);
  padding-bottom: 8px;
  margin: 42px 0 16px;
  page-break-after: avoid;
}
h2 {
  font-size: 16px;
  font-weight: 700;
  color: var(--text);
  background: var(--bg-light);
  border-left: 4px solid var(--primary);
  padding: 10px 14px;
  margin: 34px 0 12px;
  border-radius: 0 4px 4px 0;
  page-break-after: avoid;
}
h3 {
  font-size: 13px;
  font-weight: 600;
  color: #334155;
  border-bottom: 1px solid var(--border);
  padding-bottom: 5px;
  margin: 26px 0 10px;
  page-break-after: avoid;
}
h4 {
  font-size: 12px;
  font-weight: 600;
  color: var(--primary);
  margin: 18px 0 8px;
  page-break-after: avoid;
}
h5 {
  font-size: 10px;
  font-weight: 700;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  margin: 14px 0 6px;
}

/* ── PARAGRAPHS ─────────────────────────────────────── */
p { margin: 0 0 10px; }
strong { color: var(--bg-dark); }

/* ── BLOCKQUOTE ─────────────────────────────────────── */
blockquote {
  border-left: 3px solid #818cf8;
  background: #eef2ff;
  margin: 14px 0;
  padding: 10px 18px;
  border-radius: 0 6px 6px 0;
  color: #312e81;
  font-size: 12px;
}
blockquote p { margin: 2px 0; }

/* ── TABLES ─────────────────────────────────────────── */
table {
  width: 100%;
  border-collapse: collapse;
  margin: 16px 0 20px;
  font-size: 11px;
  border: 1px solid var(--border);
  border-radius: 8px;
  overflow: hidden;
}
thead th {
  background: var(--bg-dark);
  color: #f1f5f9;
  padding: 9px 12px;
  font-weight: 700;
  font-size: 10px;
  letter-spacing: 0.03em;
  border-bottom: 2px solid var(--primary);
  text-align: left;
}
tbody td {
  padding: 7px 12px;
  border-bottom: 1px solid var(--border);
  vertical-align: top;
  line-height: 1.5;
  color: #334155;
}
tbody tr:nth-child(even) { background: var(--bg-light); }
tbody td:first-child { font-weight: 600; color: var(--text); }

/* ── CODE ───────────────────────────────────────────── */
code {
  font-family: "Fira Code", "Cascadia Code", "Consolas", monospace;
  font-size: 0.86em;
  background: var(--code-bg);
  color: var(--code-color);
  padding: 1px 5px;
  border-radius: 3px;
}
.code-block {
  background: var(--bg-dark);
  color: #e2e8f0;
  padding: 14px 16px;
  border-radius: 8px;
  font-size: 10px;
  line-height: 1.65;
  margin: 10px 0 14px;
  overflow-x: auto;
  page-break-inside: avoid;
  white-space: pre-wrap;
  word-break: break-all;
}
.code-block code {
  background: none;
  padding: 0;
  color: inherit;
  font-size: inherit;
}

/* ── MERMAID ────────────────────────────────────────── */
.mermaid-wrap {
  background: var(--bg-light);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 16px;
  margin: 16px 0;
  text-align: center;
  page-break-inside: avoid;
}
pre.mermaid {
  margin: 0;
  padding: 0;
  border: none;
  background: transparent;
  text-align: center;
}
pre.mermaid svg {
  max-width: 100%;
  height: auto;
}

/* ── LISTS ──────────────────────────────────────────── */
ul, ol { padding-left: 24px; margin: 8px 0 12px; }
li { margin-bottom: 4px; line-height: 1.65; }
li::marker { color: var(--primary); font-weight: 700; }

/* ── HR ─────────────────────────────────────────────── */
hr {
  border: none;
  height: 1px;
  background: linear-gradient(to right, var(--primary), transparent);
  margin: 24px 0;
}

/* ── IMAGES ─────────────────────────────────────────── */
img { max-width: 100%; border-radius: 6px; }

/* ── PRINT HELPERS ──────────────────────────────────── */
@media print {
  h1, h2, h3, h4 { page-break-after: avoid; }
  pre, blockquote, table { page-break-inside: avoid; }
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
      primaryColor:        '#eef2ff',
      primaryBorderColor:  '#4f46e5',
      primaryTextColor:    '#1e293b',
      lineColor:           '#4f46e5',
      secondaryColor:      '#f5f3ff',
      tertiaryColor:       '#f8fafc',
      fontFamily:          '"Segoe UI", Inter, system-ui, sans-serif',
      fontSize:            '13px',
      nodeBorder:          '#4f46e5',
      clusterBkg:          '#f8fafc',
      clusterBorder:       '#c7d2fe',
      titleColor:          '#0f172a',
      edgeLabelBackground: '#f8fafc',
      activeTaskBkgColor:  '#4f46e5',
      activeTaskBorderColor: '#3730a3',
    },
    flowchart: { useMaxWidth: true, htmlLabels: true, curve: 'basis' },
    sequence:  { useMaxWidth: true, wrap: true, mirrorActors: false },
    er:        { useMaxWidth: true },
    gitGraph:  { useMaxWidth: true },
    pie:       { useMaxWidth: true },
  });
</script>
</body>
</html>`;

// ── Optional debug HTML output ─────────────────────────────────────────────
const htmlPath = outputPath.replace(/\.pdf$/i, '.html');
// Remap TOC hrefs to existing anchor ids (fix mismatched hyphenization)
// Final HTML written as-is (heading ids produced above should match TOC)
// Collapse empty anchor paragraphs into heading ids so PDF has named destinations
const collapsedHtml = fullHtml.replace(/<p>\s*<a id="([^\"]+)"><\/a>\s*<\/p>\s*<h([23])>([\s\S]*?)<\/h\2>/g,
  (m, id, level, inner) => `<h${level} id="${id}">${inner}</h${level}>`);

if (debugHtml) {
  await writeFile(htmlPath, collapsedHtml, 'utf-8');
  console.log(`🔍  Debug HTML → ${htmlPath}`);
}

// ── Render with Puppeteer ──────────────────────────────────────────────────
console.log('\n🚀  Launching headless browser…');

const puppeteer = await import('puppeteer');
const browser = await puppeteer.default.launch({
  headless: true,
  args: [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--font-render-hinting=none',
  ],
});

const page = await browser.newPage();
page.on('console', msg => {
  if (msg.type() === 'error') console.warn(`  Browser error: ${msg.text()}`);
});

console.log('📝  Loading HTML content…');
await page.setContent(collapsedHtml, { waitUntil: 'networkidle0', timeout: 60_000 });

// Wait for Mermaid to finish rendering all diagrams
console.log('🎨  Waiting for Mermaid diagrams…');
await page.waitForFunction(
  () => {
    const diagrams = document.querySelectorAll('pre.mermaid');
    if (!diagrams.length) return true;
    return [...diagrams].every(d =>
      d.querySelector('svg') || d.getAttribute('data-processed')
    );
  },
  { timeout: 30_000 }
).catch(() => console.warn('⚠  Some Mermaid diagrams may not have rendered fully.'));

// Extra buffer for SVG layout
await new Promise(r => setTimeout(r, 2_500));

console.log('🖨  Generating PDF…');
await page.pdf({
  path: outputPath,
  format: 'A4',
  printBackground: true,
  margin: { top: '20mm', bottom: '22mm', left: '18mm', right: '18mm' },
  displayHeaderFooter: true,
  headerTemplate: `
    <div style="font-size:8px;color:#94a3b8;width:100%;text-align:right;
                padding:4px 18mm 0 0;font-family:'Segoe UI',sans-serif;">
      ${title}
    </div>`,
  footerTemplate: `
    <div style="font-size:8px;color:#94a3b8;width:100%;text-align:center;
                padding:0 0 4px 0;font-family:'Segoe UI',sans-serif;">
      Page <span class="pageNumber"></span> / <span class="totalPages"></span>
    </div>`,
});

await browser.close();

const { statSync } = await import('node:fs');
const sizeKb = Math.round(statSync(outputPath).size / 1024);
console.log(`\n✅  Done → ${outputPath}  (${sizeKb} KB)`);
