// ──────────────────────────────────────────────────────────────
//  GlassCode — Glassmorphism Extension for VS Code
//  Main entry point: registers commands and handles lifecycle
// ──────────────────────────────────────────────────────────────

import * as vscode from 'vscode';
import { CSSInjector } from './injector';
import { generateGlassCSS } from './styles';

let injector: CSSInjector;
let extensionContext: vscode.ExtensionContext;

// ─── Activation ──────────────────────────────────────────────────────
export function activate(context: vscode.ExtensionContext): void {
    extensionContext = context;
    injector = new CSSInjector(context);

    // Register all commands
    context.subscriptions.push(
        vscode.commands.registerCommand('glassCode.enable', cmdEnable),
        vscode.commands.registerCommand('glassCode.disable', cmdDisable),
        vscode.commands.registerCommand('glassCode.reload', cmdReload),
        vscode.commands.registerCommand('glassCode.configureSection', cmdConfigureSection),
    );

    // Auto-apply on settings change — re-inject CSS automatically
    context.subscriptions.push(
        vscode.workspace.onDidChangeConfiguration(async (e) => {
            if (e.affectsConfiguration('glassCode')) {
                const isEnabled = context.globalState.get<boolean>('glassCode.enabled', false);
                if (isEnabled) {
                    try {
                        const css = generateGlassCSS();
                        await injector.inject(css);
                    } catch (err) {
                        handleError('update glass settings', err);
                    }
                }
                promptRestart('GlassCode settings changed. Restart to apply?');
            }
        }),
    );

    // Auto-inject on startup if previously enabled
    const wasEnabled = context.globalState.get<boolean>('glassCode.enabled', false);
    if (wasEnabled) {
        const css = generateGlassCSS();
        injector.inject(css).catch((err) => {
            console.warn('[GlassCode] Auto-inject on startup failed:', err);
        });
    }

    console.log('[GlassCode] Extension activated');
}

// ─── Deactivation ────────────────────────────────────────────
export function deactivate(): void {
    console.log('[GlassCode] Extension deactivated');
}

// ─── Commands ────────────────────────────────────────────────

async function cmdEnable(): Promise<void> {
    try {
        const css = generateGlassCSS();
        await injector.inject(css);
        await extensionContext.globalState.update('glassCode.enabled', true);
        promptRestart('Glass effect enabled! A full restart of VS Code is required.');
    } catch (err) {
        handleError('enable glass effect', err);
    }
}

async function cmdDisable(): Promise<void> {
    try {
        await injector.restore();
        await extensionContext.globalState.update('glassCode.enabled', false);
        promptRestart('Glass effect disabled. A full restart of VS Code is required.');
    } catch (err) {
        handleError('disable glass effect', err);
    }
}

async function cmdReload(): Promise<void> {
    try {
        const css = generateGlassCSS();
        await injector.inject(css);
        await extensionContext.globalState.update('glassCode.enabled', true);
        promptRestart('Glass effect reloaded. A full restart of VS Code is required.');
    } catch (err) {
        handleError('reload glass effect', err);
    }
}

async function cmdConfigureSection(): Promise<void> {
    const sections = [
        { label: '$(edit)  Editor',       section: 'editor',      description: 'Code editing area' },
        { label: '$(terminal)  Panel',    section: 'panel',       description: 'Terminal, Debug Console, Output, Ports' },
        { label: '$(files)  Sidebar',     section: 'sidebar',     description: 'Explorer, Search, Extensions panel' },
        { label: '$(menu)  Activity Bar', section: 'activityBar', description: 'Left icon bar' },
        { label: '$(info)  Status Bar',   section: 'statusBar',   description: 'Bottom information bar' },
        { label: '$(window)  Title Bar',  section: 'titleBar',    description: 'Window title bar' },
        { label: '$(browser)  Tab Bar',   section: 'tabBar',      description: 'Editor tab strip' },
    ];

    const picked = await vscode.window.showQuickPick(sections, {
        placeHolder: 'Select a section to configure',
        title: 'GlassCode — Configure Section',
    });

    if (!picked) { return; }

    const config = vscode.workspace.getConfiguration('glassCode');
    const sectionKey = picked.section;

    // Toggle enabled / disabled
    const currentEnabled = config.get<boolean>(`${sectionKey}.enabled`, true);
    const toggleAction = currentEnabled ? 'Disable' : 'Enable';

    const action = await vscode.window.showQuickPick(
        [
            { label: `${toggleAction} this section`, value: 'toggle' },
            { label: 'Set opacity', value: 'opacity' },
            { label: 'Set blur intensity', value: 'blur' },
            { label: 'Toggle glassmorphism (blur) globally', value: 'glass' },
        ],
        { placeHolder: `Configure ${picked.label}`, title: `GlassCode — ${picked.label}` },
    );

    if (!action) { return; }

    switch (action.value) {
        case 'toggle':
            await config.update(`${sectionKey}.enabled`, !currentEnabled, vscode.ConfigurationTarget.Global);
            vscode.window.showInformationMessage(
                `GlassCode: ${picked.label} ${!currentEnabled ? 'enabled' : 'disabled'}.`,
            );
            break;

        case 'opacity': {
            const input = await vscode.window.showInputBox({
                prompt: `Opacity for ${picked.label} (0.0 = transparent, 1.0 = opaque)`,
                value: String(config.get<number>(`${sectionKey}.opacity`, 0.85)),
                validateInput: (v) => {
                    const n = parseFloat(v);
                    if (isNaN(n) || n < 0 || n > 1) { return 'Enter a number between 0.0 and 1.0'; }
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
                value: String(config.get<number>(`${sectionKey}.blur`, 10)),
                validateInput: (v) => {
                    const n = parseInt(v, 10);
                    if (isNaN(n) || n < 0 || n > 50) { return 'Enter a number between 0 and 50'; }
                    return null;
                },
            });
            if (input !== undefined) {
                await config.update(`${sectionKey}.blur`, parseInt(input, 10), vscode.ConfigurationTarget.Global);
            }
            break;
        }

        case 'glass': {
            const currentGlass = config.get<boolean>('glassmorphism', true);
            await config.update('glassmorphism', !currentGlass, vscode.ConfigurationTarget.Global);
            vscode.window.showInformationMessage(
                `GlassCode: Glassmorphism blur ${!currentGlass ? 'enabled' : 'disabled'} globally.`,
            );
            break;
        }
    }
}

// ─── Helpers ─────────────────────────────────────────────────

async function promptRestart(message: string): Promise<void> {
    const choice = await vscode.window.showInformationMessage(
        message,
        'Restart Now',
        'Later',
    );
    if (choice === 'Restart Now') {
        // workbench.action.quit closes VS Code entirely.
        // The user must reopen it for main.js changes to take effect.
        // Alternatively we can just reload — it won't pick up main.js
        // changes but at least picks up CSS changes.
        vscode.commands.executeCommand('workbench.action.reloadWindow');
    }
}

function handleError(action: string, err: unknown): void {
    const msg = err instanceof Error ? err.message : String(err);

    if (msg.includes('EACCES') || msg.includes('EPERM')) {
        vscode.window.showErrorMessage(
            `GlassCode: Permission denied while trying to ${action}. ` +
            `Try running VS Code as Administrator (Windows) or with sudo (Linux/macOS).`,
        );
    } else {
        vscode.window.showErrorMessage(`GlassCode: Failed to ${action} — ${msg}`);
    }

    console.error(`[GlassCode] Error (${action}):`, err);
}
