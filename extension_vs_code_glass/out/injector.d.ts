import * as vscode from 'vscode';
export declare class CSSInjector {
    private context;
    constructor(context: vscode.ExtensionContext);
    inject(css: string): Promise<void>;
    restore(): Promise<void>;
    isInjected(): boolean;
    private resolveMainJsPath;
    private patchMainJs;
    private restoreMainJs;
    private stripJsMarkers;
    private injectCSS;
    private restoreHTML;
    private stripHtmlMarkers;
    private adjustSettings;
    private restoreSettings;
    private resolveWorkbenchPath;
    private backupProductJson;
    private updateChecksumForFile;
    private restoreProductJson;
    private escapeRegex;
}
//# sourceMappingURL=injector.d.ts.map