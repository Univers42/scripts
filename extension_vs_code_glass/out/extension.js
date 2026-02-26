"use strict";
// ──────────────────────────────────────────────────────────────
//  GlassCode — Glassmorphism Extension for VS Code
//  Main entry point: registers commands and handles lifecycle
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
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const injector_1 = require("./injector");
const styles_1 = require("./styles");
let injector;
let extensionContext;
// ─── Activation ──────────────────────────────────────────────────────
function activate(context) {
    extensionContext = context;
    injector = new injector_1.CSSInjector(context);
    // Register all commands
    context.subscriptions.push(vscode.commands.registerCommand('glassCode.enable', cmdEnable), vscode.commands.registerCommand('glassCode.disable', cmdDisable), vscode.commands.registerCommand('glassCode.reload', cmdReload), vscode.commands.registerCommand('glassCode.configureSection', cmdConfigureSection));
    // Auto-apply on settings change — re-inject CSS automatically
    context.subscriptions.push(vscode.workspace.onDidChangeConfiguration(async (e) => {
        if (e.affectsConfiguration('glassCode')) {
            const isEnabled = context.globalState.get('glassCode.enabled', false);
            if (isEnabled) {
                try {
                    const css = (0, styles_1.generateGlassCSS)();
                    await injector.inject(css);
                }
                catch (err) {
                    handleError('update glass settings', err);
                }
            }
            promptRestart('GlassCode settings changed. Restart to apply?');
        }
    }));
    // Auto-inject on startup if previously enabled
    const wasEnabled = context.globalState.get('glassCode.enabled', false);
    if (wasEnabled) {
        const css = (0, styles_1.generateGlassCSS)();
        injector.inject(css).catch((err) => {
            console.warn('[GlassCode] Auto-inject on startup failed:', err);
        });
    }
    console.log('[GlassCode] Extension activated');
}
// ─── Deactivation ────────────────────────────────────────────
function deactivate() {
    console.log('[GlassCode] Extension deactivated');
}
// ─── Commands ────────────────────────────────────────────────
async function cmdEnable() {
    try {
        const css = (0, styles_1.generateGlassCSS)();
        await injector.inject(css);
        await extensionContext.globalState.update('glassCode.enabled', true);
        promptRestart('Glass effect enabled! A full restart of VS Code is required.');
    }
    catch (err) {
        handleError('enable glass effect', err);
    }
}
async function cmdDisable() {
    try {
        await injector.restore();
        await extensionContext.globalState.update('glassCode.enabled', false);
        promptRestart('Glass effect disabled. A full restart of VS Code is required.');
    }
    catch (err) {
        handleError('disable glass effect', err);
    }
}
async function cmdReload() {
    try {
        const css = (0, styles_1.generateGlassCSS)();
        await injector.inject(css);
        await extensionContext.globalState.update('glassCode.enabled', true);
        promptRestart('Glass effect reloaded. A full restart of VS Code is required.');
    }
    catch (err) {
        handleError('reload glass effect', err);
    }
}
async function cmdConfigureSection() {
    const sections = [
        { label: '$(edit)  Editor', section: 'editor', description: 'Code editing area' },
        { label: '$(terminal)  Panel', section: 'panel', description: 'Terminal, Debug Console, Output, Ports' },
        { label: '$(files)  Sidebar', section: 'sidebar', description: 'Explorer, Search, Extensions panel' },
        { label: '$(menu)  Activity Bar', section: 'activityBar', description: 'Left icon bar' },
        { label: '$(info)  Status Bar', section: 'statusBar', description: 'Bottom information bar' },
        { label: '$(window)  Title Bar', section: 'titleBar', description: 'Window title bar' },
        { label: '$(browser)  Tab Bar', section: 'tabBar', description: 'Editor tab strip' },
    ];
    const picked = await vscode.window.showQuickPick(sections, {
        placeHolder: 'Select a section to configure',
        title: 'GlassCode — Configure Section',
    });
    if (!picked) {
        return;
    }
    const config = vscode.workspace.getConfiguration('glassCode');
    const sectionKey = picked.section;
    // Toggle enabled / disabled
    const currentEnabled = config.get(`${sectionKey}.enabled`, true);
    const toggleAction = currentEnabled ? 'Disable' : 'Enable';
    const action = await vscode.window.showQuickPick([
        { label: `${toggleAction} this section`, value: 'toggle' },
        { label: 'Set opacity', value: 'opacity' },
        { label: 'Set blur intensity', value: 'blur' },
        { label: 'Toggle glassmorphism (blur) globally', value: 'glass' },
    ], { placeHolder: `Configure ${picked.label}`, title: `GlassCode — ${picked.label}` });
    if (!action) {
        return;
    }
    switch (action.value) {
        case 'toggle':
            await config.update(`${sectionKey}.enabled`, !currentEnabled, vscode.ConfigurationTarget.Global);
            vscode.window.showInformationMessage(`GlassCode: ${picked.label} ${!currentEnabled ? 'enabled' : 'disabled'}.`);
            break;
        case 'opacity': {
            const input = await vscode.window.showInputBox({
                prompt: `Opacity for ${picked.label} (0.0 = transparent, 1.0 = opaque)`,
                value: String(config.get(`${sectionKey}.opacity`, 0.85)),
                validateInput: (v) => {
                    const n = parseFloat(v);
                    if (isNaN(n) || n < 0 || n > 1) {
                        return 'Enter a number between 0.0 and 1.0';
                    }
                    return null;
                },
            });
            if (input !== undefined) {
                await config.update(`${sectionKey}.opacity`, parseFloat(input), vscode.ConfigurationTarget.Global);
            }
            break;
        }
        case 'blur': {
            const input = await vscode.window.showInputBox({
                prompt: `Blur radius in pixels for ${picked.label} (0 = no blur, 50 = max)`,
                value: String(config.get(`${sectionKey}.blur`, 10)),
                validateInput: (v) => {
                    const n = parseInt(v, 10);
                    if (isNaN(n) || n < 0 || n > 50) {
                        return 'Enter a number between 0 and 50';
                    }
                    return null;
                },
            });
            if (input !== undefined) {
                await config.update(`${sectionKey}.blur`, parseInt(input, 10), vscode.ConfigurationTarget.Global);
            }
            break;
        }
        case 'glass': {
            const currentGlass = config.get('glassmorphism', true);
            await config.update('glassmorphism', !currentGlass, vscode.ConfigurationTarget.Global);
            vscode.window.showInformationMessage(`GlassCode: Glassmorphism blur ${!currentGlass ? 'enabled' : 'disabled'} globally.`);
            break;
        }
    }
}
// ─── Helpers ─────────────────────────────────────────────────
async function promptRestart(message) {
    const choice = await vscode.window.showInformationMessage(message, 'Restart Now', 'Later');
    if (choice === 'Restart Now') {
        // workbench.action.quit closes VS Code entirely.
        // The user must reopen it for main.js changes to take effect.
        // Alternatively we can just reload — it won't pick up main.js
        // changes but at least picks up CSS changes.
        vscode.commands.executeCommand('workbench.action.reloadWindow');
    }
}
function handleError(action, err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('EACCES') || msg.includes('EPERM')) {
        vscode.window.showErrorMessage(`GlassCode: Permission denied while trying to ${action}. ` +
            `Try running VS Code as Administrator (Windows) or with sudo (Linux/macOS).`);
    }
    else {
        vscode.window.showErrorMessage(`GlassCode: Failed to ${action} — ${msg}`);
    }
    console.error(`[GlassCode] Error (${action}):`, err);
}
//# sourceMappingURL=extension.js.map