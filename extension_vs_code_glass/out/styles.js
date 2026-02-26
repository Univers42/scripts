"use strict";
// ──────────────────────────────────────────────────────────────
//  GlassCode — Glassmorphism CSS Generator
//
//  Reads the user's configuration and builds the CSS that gets
//  injected into VS Code's workbench HTML.
//
//  Supported sections and their DOM selectors are mapped below.
//  Each section can be independently enabled, with its own
//  opacity and blur radius settings.
// ──────────────────────────────────────────────────────────────
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateGlassCSS = generateGlassCSS;
const vscode = __importStar(require("vscode"));
const SECTION_DEFS = [
    {
        key: 'editor',
        label: 'Editor',
        selectors: [
            '.editor-instance .monaco-editor',
            '.editor-instance .monaco-editor .overflow-guard',
            '.editor-instance .monaco-editor .margin',
            '.editor-group-container > .editor-container',
            '.monaco-editor .lines-content',
            '.monaco-editor .view-lines',
            '.editor-group-container',
            '.split-view-view > .editor-group-container',
        ],
    },
    {
        key: 'panel',
        label: 'Panel (Terminal / Debug / Output / Ports)',
        selectors: [
            '.part.panel',
            '.panel .content',
            '.panel .pane-body',
            '.terminal-wrapper',
            '.terminal-outer-container',
            '.integrated-terminal',
            '.xterm-viewport',
            '.xterm .xterm-screen',
            '.repl .repl-tree',
            '.output-view',
            '.markers-panel',
        ],
    },
    {
        key: 'sidebar',
        label: 'Sidebar',
        selectors: [
            '.part.sidebar',
            '.sidebar .composite.title',
            '.sidebar .pane-body',
            '.sidebar .content',
            '.explorer-folders-view',
            '.extensions-list',
        ],
    },
    {
        key: 'activityBar',
        label: 'Activity Bar',
        selectors: [
            '.part.activitybar',
            '.activitybar .content',
        ],
    },
    {
        key: 'statusBar',
        label: 'Status Bar',
        selectors: [
            '.part.statusbar',
            '.statusbar',
        ],
    },
    {
        key: 'titleBar',
        label: 'Title Bar',
        selectors: [
            '.part.titlebar',
            '.titlebar-container',
        ],
    },
    {
        key: 'tabBar',
        label: 'Tab Bar',
        selectors: [
            '.editor .title.tabs',
            '.tabs-container',
            '.tab',
            '.editor-group-container > .title',
        ],
    },
];
function readSectionConfig(sectionKey) {
    const cfg = vscode.workspace.getConfiguration('glassCode');
    return {
        enabled: cfg.get(`${sectionKey}.enabled`, true),
        opacity: cfg.get(`${sectionKey}.opacity`, 0.85),
        blur: cfg.get(`${sectionKey}.blur`, 10),
    };
}
// ─── CSS Builder ─────────────────────────────────────────────
/**
 * Generate the complete CSS string for all enabled sections
 * based on the user's current configuration.
 */
function generateGlassCSS() {
    const cfg = vscode.workspace.getConfiguration('glassCode');
    const glassmorphism = cfg.get('glassmorphism', true);
    const bgImage = cfg.get('backgroundImage', '');
    const bgOpacity = cfg.get('backgroundOpacity', 0.15);
    const lines = [];
    // ── Header ───────────────────────────────────────────────
    lines.push('/* ═══════════════════════════════════════════════════ */');
    lines.push('/*  GlassCode — Auto-generated glassmorphism styles   */');
    lines.push('/*  DO NOT EDIT — regenerated on every "Reload"       */');
    lines.push('/* ═══════════════════════════════════════════════════ */');
    lines.push('');
    // ── Optional background wallpaper ────────────────────────
    if (bgImage) {
        const url = bgImage.startsWith('http') || bgImage.startsWith('data:')
            ? bgImage
            : `file://${bgImage.replace(/\\/g, '/')}`;
        lines.push('/* Background wallpaper */');
        lines.push('body::before {');
        lines.push('  content: "";');
        lines.push('  position: fixed;');
        lines.push('  inset: 0;');
        lines.push(`  background: url("${url}") center/cover no-repeat;`);
        lines.push(`  opacity: ${bgOpacity};`);
        lines.push('  pointer-events: none;');
        lines.push('  z-index: -1;');
        lines.push('}');
        lines.push('');
    }
    // ── Global workbench base — make the root and body truly transparent ──
    // Without this, the Electron window's transparent:true has no effect
    // because the HTML/body background covers everything.
    lines.push('/* Make the root elements truly transparent for Electron transparency */');
    lines.push('html, body {');
    lines.push('  background-color: transparent !important;');
    lines.push('  background: transparent !important;');
    lines.push('}');
    lines.push('');
    lines.push('.monaco-workbench {');
    lines.push('  background-color: transparent !important;');
    lines.push('  background: transparent !important;');
    lines.push('}');
    lines.push('');
    // ── Transparent container chain ──────────────────────────
    // Make all intermediate wrapper elements transparent so the
    // background image bleeds through to the glassmorphism layers.
    lines.push('/* Transparent container chain — lets background show through */');
    const transparentChain = [
        'body',
        '.monaco-grid-view',
        '.monaco-grid-branch-node',
        '.monaco-split-view2',
        '.monaco-split-view2 > .monaco-scrollable-element',
        '.split-view-container',
        '.split-view-view',
        '.editor-instance',
        '.editor-container',
        '.overflow-guard',
        '.minimap-decorations-layer',
        '.monaco-workbench .auxiliarybar',
        '.monaco-workbench .part > .content',
        '.monaco-workbench .pane-composite-part > .content',
    ];
    lines.push(transparentChain.join(',\n') + ' {');
    lines.push('  background-color: transparent !important;');
    lines.push('}');
    lines.push('');
    // ── Per-section styles ───────────────────────────────────
    for (const section of SECTION_DEFS) {
        const sc = readSectionConfig(section.key);
        if (!sc.enabled) {
            continue;
        }
        lines.push(`/* ── ${section.label} ── */`);
        const selectorBlock = section.selectors.join(',\n');
        lines.push(`${selectorBlock} {`);
        lines.push(`  background-color: rgba(30, 30, 30, ${sc.opacity.toFixed(2)}) !important;`);
        if (glassmorphism && sc.blur > 0) {
            lines.push(`  backdrop-filter: blur(${sc.blur}px) saturate(180%) !important;`);
            lines.push(`  -webkit-backdrop-filter: blur(${sc.blur}px) saturate(180%) !important;`);
        }
        // Subtle border for the frosted look
        lines.push('  border: 1px solid rgba(255, 255, 255, 0.05) !important;');
        lines.push('}');
        lines.push('');
    }
    // ── Light theme variant ──────────────────────────────────
    lines.push('/* Light theme adjustments */');
    lines.push('.vs .monaco-workbench {');
    lines.push('  background-color: transparent !important;');
    lines.push('}');
    lines.push('');
    for (const section of SECTION_DEFS) {
        const sc = readSectionConfig(section.key);
        if (!sc.enabled) {
            continue;
        }
        const selectorBlock = section.selectors
            .map((s) => `.vs ${s}`)
            .join(',\n');
        lines.push(`${selectorBlock} {`);
        lines.push(`  background-color: rgba(245, 245, 245, ${sc.opacity.toFixed(2)}) !important;`);
        if (glassmorphism && sc.blur > 0) {
            lines.push(`  backdrop-filter: blur(${sc.blur}px) saturate(180%) !important;`);
            lines.push(`  -webkit-backdrop-filter: blur(${sc.blur}px) saturate(180%) !important;`);
        }
        lines.push('  border: 1px solid rgba(0, 0, 0, 0.06) !important;');
        lines.push('}');
        lines.push('');
    }
    // ── Smooth transitions ───────────────────────────────────
    lines.push('/* Smooth transitions for opacity changes */');
    const allSelectors = SECTION_DEFS.flatMap((s) => s.selectors);
    lines.push(`${allSelectors.join(',\n')} {`);
    lines.push('  transition: background-color 0.3s ease, backdrop-filter 0.3s ease !important;');
    lines.push('}');
    lines.push('');
    // ── Scrollbar styling for consistency ────────────────────
    lines.push('/* Semi-transparent scrollbars to match the glass aesthetic */');
    lines.push('.monaco-scrollable-element > .scrollbar > .slider {');
    lines.push('  background: rgba(150, 150, 150, 0.35) !important;');
    lines.push('  border-radius: 4px !important;');
    lines.push('}');
    lines.push('.monaco-scrollable-element > .scrollbar > .slider:hover {');
    lines.push('  background: rgba(150, 150, 150, 0.55) !important;');
    lines.push('}');
    lines.push('');
    // ── Minimap transparency ─────────────────────────────────
    lines.push('/* Minimap glass effect */');
    lines.push('.minimap {');
    lines.push('  opacity: 0.75 !important;');
    lines.push('}');
    lines.push('');
    return lines.join('\n');
}
//# sourceMappingURL=styles.js.map