/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   add_42_headers.js                                  :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: dlesieur <dlesieur@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/05/18 21:19:26 by dlesieur          #+#    #+#             */
/*   Updated: 2026/05/18 21:19:26 by dlesieur         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#!/usr/bin/env node
// Prepend the 42 school header to every eligible code file that does not have one yet.
// Reuses the header.js module from the locally installed kube.42header VSCode extension.
//
// Usage (from anywhere):
//   node vendor/scripts/add_42_headers.js [--dry-run] [path ...]
//
// Options:
//   --dry-run   Print which files would be modified without touching them.
//   path        One or more dirs / files to process (default: repo root).
//
// Config (env vars, optional):
//   FT_LOGIN    42 login        (default: $USER or "marvin")
//   FT_SCHOOL   school domain   (default: "42.fr")
//   HEADER_EXT  Path to kube.42header VSCode extension (auto-detected)

'use strict';

const fs   = require('fs');
const path = require('path');

// ── locate the installed extension ────────────────────────────────────────────
function findExtension() {
  if (process.env.HEADER_EXT) return process.env.HEADER_EXT;
  const base = path.join(process.env.HOME || '/root', '.vscode', 'extensions');
  try {
    const match = fs.readdirSync(base).find(d => d.startsWith('kube.42header-'));
    if (match) return path.join(base, match);
  } catch (_) {}
  return null;
}

const extDir = findExtension();
if (!extDir) {
  console.error('42header extension not found. Install it in VSCode (kube.42header) or set HEADER_EXT.');
  process.exit(1);
}

// Inject the extension's node_modules (only "moment" is needed) into the search path.
require('module').Module._nodeModulePaths = (function (orig) {
  return function (from) {
    return orig(from).concat([path.join(extDir, 'node_modules')]);
  };
})(require('module').Module._nodeModulePaths);
require('module')._resolveFilename = (function (orig) {
  return function (request, parent, ...rest) {
    try { return orig(request, parent, ...rest); }
    catch (_) {
      const candidate = path.join(extDir, 'node_modules', request);
      try { return require.resolve(candidate); } catch (__) {}
      throw _;
    }
  };
})(require('module')._resolveFilename);

const headerJs  = require(path.join(extDir, 'out', 'src', 'header.js'));
const moment    = require(path.join(extDir, 'node_modules', 'moment'));

// ── config ────────────────────────────────────────────────────────────────────
const LOGIN  = process.env.FT_LOGIN  || process.env.USER || 'marvin';
const SCHOOL = process.env.FT_SCHOOL || '42.fr';
const AUTHOR = `${LOGIN} <${LOGIN}@student.${SCHOOL}>`;

// ── extension-to-languageId map ───────────────────────────────────────────────
const EXT_LANG = {
  '.c':    'c',      '.h':   'c',
  '.cpp':  'cpp',    '.hpp': 'cpp',   '.cc': 'cpp',
  '.ts':   'typescript',              '.tsx': 'typescriptreact',
  '.js':   'javascript', '.mjs': 'javascript', '.cjs': 'javascript',
  '.jsx':  'javascriptreact',
  '.css':  'css',    '.scss': 'scss',
  '.py':   'python',
  '.sh':   'shellscript', '.bash': 'shellscript', '.zsh': 'shellscript',
  '.sql':  'sql',
  '.rs':   'rust',   '.go': 'go',
};

// Makefile by filename (no extension)
const NAME_LANG = {
  'makefile': 'makefile',
  'Makefile': 'makefile',
  'GNUmakefile': 'makefile',
};

// ── skip rules ────────────────────────────────────────────────────────────────
const SKIP_DIRS = new Set([
  'node_modules', '.git', 'dist', 'build', 'out', '.next', '.nuxt',
  'coverage', '__pycache__', '.cache', 'archive', '.venv', 'venv', '.venv-pdf',
]);

// Filename globs that are config / generated / sensitive — skip them.
const SKIP_FILE_RE = [
  /^\.env(\..*)?$/,          // .env  .env.local  .env.example
  /package-lock\.json$/,
  /yarn\.lock$/,
  /pnpm-lock\.yaml$/,
  /\.lock$/,
  /\.min\.(js|css)$/,         // minified
  /\.(map|d\.ts)$/,           // source maps, declaration files
];

// ── CLI args ──────────────────────────────────────────────────────────────────
const args    = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const roots   = args.filter(a => !a.startsWith('-'));

// Default: two levels up from vendor/scripts/
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const SCAN_ROOTS = roots.length ? roots.map(r => path.resolve(r)) : [REPO_ROOT];

// ── helpers ───────────────────────────────────────────────────────────────────
function langFor(filepath) {
  const base = path.basename(filepath);
  if (NAME_LANG[base]) return NAME_LANG[base];
  const ext = path.extname(filepath).toLowerCase();
  return EXT_LANG[ext] || null;
}

function shouldSkip(filepath) {
  const base = path.basename(filepath);
  return SKIP_FILE_RE.some(re => re.test(base));
}

function* walk(dir) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
  catch (_) { return; }
  for (const e of entries) {
    if (SKIP_DIRS.has(e.name)) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { yield* walk(full); }
    else if (e.isFile())  { yield full; }
  }
}

// ── main ──────────────────────────────────────────────────────────────────────
let processed = 0, skipped = 0, errors = 0;

for (const root of SCAN_ROOTS) {
  const stat = fs.statSync(root, { throwIfNoEntry: false });
  if (!stat) { console.warn(`Not found: ${root}`); continue; }
  const files = stat.isDirectory() ? walk(root) : [root];

  for (const file of files) {
    if (shouldSkip(file)) continue;

    const lang = langFor(file);
    if (!lang || !headerJs.supportsLanguage(lang)) continue;

    let text;
    try { text = fs.readFileSync(file, 'utf8'); }
    catch (_) { continue; }

    // Already has a header — skip.
    if (headerJs.extractHeader(text)) { skipped++; continue; }

    const now      = moment();
    const filename = path.basename(file);
    const header   = headerJs.renderHeader(lang, {
      filename,
      author:    AUTHOR,
      createdAt: now,
      createdBy: LOGIN,
      updatedAt: now,
      updatedBy: LOGIN,
    });

    // Keep shebang as the first line — insert header after it.
    let output;
    if (text.startsWith('#!')) {
      const nl = text.indexOf('\n');
      const shebang = nl === -1 ? text : text.slice(0, nl + 1);
      const rest    = nl === -1 ? ''   : text.slice(nl + 1);
      output = shebang + header + rest;
    } else {
      output = header + text;
    }

    if (DRY_RUN) {
      console.log(`[dry-run] would add header → ${path.relative(REPO_ROOT, file)}`);
    } else {
      try {
        fs.writeFileSync(file, output);
        console.log(`✓ ${path.relative(REPO_ROOT, file)}`);
      } catch (err) {
        console.error(`✗ ${file}: ${err.message}`);
        errors++;
        continue;
      }
    }
    processed++;
  }
}

console.log(`\nDone — ${processed} file(s) updated, ${skipped} already had a header, ${errors} error(s).`);
if (errors) process.exit(1);
