// ──────────────────────────────────────────────────────────────
//  GlassCode — CSS + Electron Injector
//
//  For real transparency VS Code's Electron BrowserWindow must
//  be created with `transparent: true`.  CSS alone only changes
//  colours *within* the already-opaque window.
//
//  This injector:
//    1. Patches VS Code's main.js  → adds transparent:true to
//       the BrowserWindow constructor options.
//    2. Writes a glasscode-custom.css file next to workbench.html
//       and adds a <link> tag AFTER the main CSS.
//    3. Surgically updates MD5 checksums in product.json so the
//       "corrupt installation" warning does not appear.
//    4. Adjusts VS Code settings for terminal GPU acceleration
//       and transparent terminal background.
//    5. All changes are reversible via `restore()`.
// ──────────────────────────────────────────────────────────────

import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';

const MARKER_START = '<!-- GLASSCODE_CSS_START -->';
const MARKER_END   = '<!-- GLASSCODE_CSS_END -->';
const JS_MARKER_START = '/* GLASSCODE_START */';
const JS_MARKER_END   = '/* GLASSCODE_END */';
const BACKUP_EXT   = '.glasscode-backup';
const CSS_FILENAME = 'glasscode-custom.css';

export class CSSInjector {
    private context: vscode.ExtensionContext;

    constructor(context: vscode.ExtensionContext) {
        this.context = context;
    }

    // ─── Public API ──────────────────────────────────────────

    async inject(css: string): Promise<void> {
        // 1. Patch the Electron main.js for transparent BrowserWindow
        await this.patchMainJs();

        // 2. Inject CSS into workbench HTML
        await this.injectCSS(css);

        // 3. Adjust VS Code settings for compatibility
        await this.adjustSettings();
    }

    async restore(): Promise<void> {
        // 1. Restore main.js
        await this.restoreMainJs();

        // 2. Restore workbench HTML
        await this.restoreHTML();

        // 3. Restore VS Code settings
        await this.restoreSettings();

        // 4. Restore product.json checksums
        this.restoreProductJson();
    }

    isInjected(): boolean {
        try {
            const html = fs.readFileSync(this.resolveWorkbenchPath(), 'utf-8');
            return html.includes(MARKER_START);
        } catch {
            return false;
        }
    }

    // ─── Main.js Patching ────────────────────────────────────

    private resolveMainJsPath(): string {
        const appRoot = vscode.env.appRoot;
        const candidates = [
            path.join(appRoot, 'out', 'main.js'),
            path.join(appRoot, 'out', 'vs', 'code', 'electron-main', 'main.js'),
        ];
        for (const p of candidates) {
            if (fs.existsSync(p)) { return p; }
        }
        throw new Error('[GlassCode] Could not find VS Code main.js');
    }

    private async patchMainJs(): Promise<void> {
        const mainJsPath = this.resolveMainJsPath();
        let js = fs.readFileSync(mainJsPath, 'utf-8');

        // Backup once
        const backup = mainJsPath + BACKUP_EXT;
        if (!fs.existsSync(backup)) {
            fs.writeFileSync(backup, js, 'utf-8');
            console.log(`[GlassCode] main.js backup created: ${backup}`);
            this.backupProductJson();
        }

        // Strip any previous patch
        js = this.stripJsMarkers(js);

        // Check if already contains our transparent patch (shouldn't after stripping)
        if (js.includes('frame:false,transparent:true,experimentalDarkMode')) {
            console.log('[GlassCode] main.js already patched');
        } else if (js.includes('experimentalDarkMode')) {
            // Inject frame:false,transparent:true before experimentalDarkMode
            js = js.replace(
                /experimentalDarkMode/,
                'frame:false,transparent:true,experimentalDarkMode',
            );
            console.log('[GlassCode] Patched main.js with transparent:true');
        } else {
            console.warn('[GlassCode] Could not find experimentalDarkMode anchor in main.js');
        }

        fs.writeFileSync(mainJsPath, js, 'utf-8');
        this.updateChecksumForFile(mainJsPath);
    }

    private async restoreMainJs(): Promise<void> {
        const mainJsPath = this.resolveMainJsPath();
        const backup = mainJsPath + BACKUP_EXT;
        if (fs.existsSync(backup)) {
            fs.copyFileSync(backup, mainJsPath);
            console.log(`[GlassCode] main.js restored from backup`);
        } else {
            // Remove our patch manually
            let js = fs.readFileSync(mainJsPath, 'utf-8');
            js = js.replace('frame:false,transparent:true,experimentalDarkMode', 'experimentalDarkMode');
            js = this.stripJsMarkers(js);
            fs.writeFileSync(mainJsPath, js, 'utf-8');
            console.log('[GlassCode] main.js patch removed');
        }
    }

    private stripJsMarkers(js: string): string {
        const regex = new RegExp(
            `\\n?${this.escapeRegex(JS_MARKER_START)}[\\s\\S]*?${this.escapeRegex(JS_MARKER_END)}\\n?`,
            'g',
        );
        return js.replace(regex, '');
    }

    // ─── CSS Injection ───────────────────────────────────────

    private async injectCSS(css: string): Promise<void> {
        const htmlPath = this.resolveWorkbenchPath();
        const htmlDir  = path.dirname(htmlPath);
        const cssPath  = path.join(htmlDir, CSS_FILENAME);

        let html = fs.readFileSync(htmlPath, 'utf-8');

        // Backup once
        const backup = htmlPath + BACKUP_EXT;
        if (!fs.existsSync(backup)) {
            const cleanHtml = this.stripHtmlMarkers(html);
            fs.writeFileSync(backup, cleanHtml, 'utf-8');
            console.log(`[GlassCode] workbench.html backup created`);
        }

        // Strip previous injection
        html = this.stripHtmlMarkers(html);

        // Write CSS to file
        fs.writeFileSync(cssPath, css, 'utf-8');

        // Build link tag (placed after </head> to appear after main CSS in cascade)
        const linkTag = `\n${MARKER_START}\n\t\t<link rel="stylesheet" href="./${CSS_FILENAME}">\n${MARKER_END}`;

        if (html.includes('</head>')) {
            html = html.replace('</head>', `</head>${linkTag}`);
        } else {
            throw new Error('[GlassCode] Could not find </head> in workbench HTML.');
        }

        fs.writeFileSync(htmlPath, html, 'utf-8');
        this.updateChecksumForFile(htmlPath);
        console.log(`[GlassCode] CSS injected into workbench`);
    }

    private async restoreHTML(): Promise<void> {
        const htmlPath = this.resolveWorkbenchPath();
        const htmlDir  = path.dirname(htmlPath);
        const cssPath  = path.join(htmlDir, CSS_FILENAME);
        const backup   = htmlPath + BACKUP_EXT;

        if (fs.existsSync(backup)) {
            fs.copyFileSync(backup, htmlPath);
            console.log('[GlassCode] workbench.html restored from backup');
        } else {
            let html = fs.readFileSync(htmlPath, 'utf-8');
            html = this.stripHtmlMarkers(html);
            fs.writeFileSync(htmlPath, html, 'utf-8');
        }

        if (fs.existsSync(cssPath)) {
            fs.unlinkSync(cssPath);
        }
    }

    private stripHtmlMarkers(html: string): string {
        const regex = new RegExp(
            `\\n?${this.escapeRegex(MARKER_START)}[\\s\\S]*?${this.escapeRegex(MARKER_END)}\\n?`,
            'g',
        );
        return html.replace(regex, '');
    }

    // ─── Settings ────────────────────────────────────────────

    private async adjustSettings(): Promise<void> {
        try {
            const config = vscode.workspace.getConfiguration();

            // Save previous settings
            const prev = this.context.globalState.get<Record<string, unknown>>('glassCode.prevSettings', {});
            if (!prev.saved) {
                const colorCustom = config.get<Record<string, string>>('workbench.colorCustomizations', {});
                prev.saved = true;
                prev.gpuAcceleration = config.get<string>('terminal.integrated.gpuAcceleration');
                prev.terminalBackground = colorCustom['terminal.background'];
                await this.context.globalState.update('glassCode.prevSettings', prev);
            }

            // Terminal GPU acceleration must be off for transparency
            await config.update('terminal.integrated.gpuAcceleration', 'off', vscode.ConfigurationTarget.Global);

            // Make terminal background transparent
            const colorCustom = config.get<Record<string, string>>('workbench.colorCustomizations', {});
            colorCustom['terminal.background'] = '#00000000';
            await config.update('workbench.colorCustomizations', colorCustom, vscode.ConfigurationTarget.Global);

            console.log('[GlassCode] VS Code settings adjusted');
        } catch (err) {
            console.warn('[GlassCode] Failed to adjust settings:', err);
        }
    }

    private async restoreSettings(): Promise<void> {
        try {
            const prev = this.context.globalState.get<Record<string, unknown>>('glassCode.prevSettings', {});
            if (prev.saved) {
                const config = vscode.workspace.getConfiguration();

                if (prev.gpuAcceleration !== undefined) {
                    await config.update('terminal.integrated.gpuAcceleration', prev.gpuAcceleration, vscode.ConfigurationTarget.Global);
                }

                const colorCustom = config.get<Record<string, string>>('workbench.colorCustomizations', {});
                if (prev.terminalBackground !== undefined) {
                    colorCustom['terminal.background'] = prev.terminalBackground as string;
                } else {
                    delete colorCustom['terminal.background'];
                }
                await config.update('workbench.colorCustomizations', colorCustom, vscode.ConfigurationTarget.Global);

                await this.context.globalState.update('glassCode.prevSettings', {});
            }
        } catch (err) {
            console.warn('[GlassCode] Failed to restore settings:', err);
        }
    }

    // ─── Path Resolution ─────────────────────────────────────

    private resolveWorkbenchPath(): string {
        const appRoot = vscode.env.appRoot;
        const candidates = [
            path.join(appRoot, 'out', 'vs', 'code', 'electron-sandbox', 'workbench', 'workbench.esm.html'),
            path.join(appRoot, 'out', 'vs', 'code', 'electron-sandbox', 'workbench', 'workbench.html'),
            path.join(appRoot, 'out', 'vs', 'code', 'electron-browser', 'workbench', 'workbench.html'),
        ];
        for (const p of candidates) {
            if (fs.existsSync(p)) { return p; }
        }
        throw new Error(
            `[GlassCode] Could not find workbench HTML.\n` +
            `Searched:\n${candidates.map((c) => `  - ${c}`).join('\n')}`,
        );
    }

    // ─── Checksum Helpers ────────────────────────────────────

    private backupProductJson(): void {
        try {
            const appRoot = vscode.env.appRoot;
            const p = path.join(appRoot, 'product.json');
            const b = p + BACKUP_EXT;
            if (fs.existsSync(p) && !fs.existsSync(b)) {
                fs.copyFileSync(p, b);
                console.log('[GlassCode] product.json backup created');
            }
        } catch (err) {
            console.warn('[GlassCode] Failed to backup product.json:', err);
        }
    }

    private updateChecksumForFile(filePath: string): void {
        try {
            const appRoot = vscode.env.appRoot;
            const productJsonPath = path.join(appRoot, 'product.json');
            if (!fs.existsSync(productJsonPath)) { return; }

            const productRaw = fs.readFileSync(productJsonPath, 'utf-8');

            // Build possible keys
            const rel = path.relative(appRoot, filePath).replace(/\\/g, '/');
            const withoutOut = rel.replace(/^out\//, '');

            let checksumKey: string | null = null;
            for (const candidate of [rel, withoutOut]) {
                if (productRaw.includes(`"${candidate}"`)) {
                    checksumKey = candidate;
                    break;
                }
            }
            if (!checksumKey) {
                console.log(`[GlassCode] No checksum entry for ${rel}`);
                return;
            }

            // Compute MD5 (what VS Code uses for HTML) or SHA-256 (for JS/CSS)
            const fileBytes = fs.readFileSync(filePath);
            const isHtml = filePath.endsWith('.html');
            const algo = isHtml ? 'md5' : 'sha256';
            const newHash = crypto.createHash(algo)
                .update(fileBytes)
                .digest('base64')
                .replace(/=+$/, '');

            // Surgical replacement
            const re = new RegExp(`("${this.escapeRegex(checksumKey)}"\\s*:\\s*")([^"]*)(")` );
            if (!re.test(productRaw)) {
                console.log(`[GlassCode] Could not match checksum regex for ${checksumKey}`);
                return;
            }
            const updated = productRaw.replace(re, `$1${newHash}$3`);
            fs.writeFileSync(productJsonPath, updated, 'utf-8');
            console.log(`[GlassCode] Checksum updated for ${checksumKey}`);
        } catch (err) {
            console.warn('[GlassCode] Checksum update failed:', err);
        }
    }

    private restoreProductJson(): void {
        try {
            const appRoot = vscode.env.appRoot;
            const p = path.join(appRoot, 'product.json');
            const b = p + BACKUP_EXT;
            if (fs.existsSync(b)) {
                fs.copyFileSync(b, p);
                console.log('[GlassCode] product.json restored from backup');
            }
        } catch (err) {
            console.warn('[GlassCode] Failed to restore product.json:', err);
        }
    }

    private escapeRegex(str: string): string {
        return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
}
