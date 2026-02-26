# GlassCode — Glassmorphism for VS Code

A custom VS Code extension that applies **glassmorphism** (frosted glass transparency) effects to different sections of the editor. Keep your focus while working in a beautiful, modern interface.

---

## Features

- **Per-section control** — Enable/disable glass effects independently for:
  - Editor (code editing space)
  - Panel (Terminal, Debug Console, Output, Ports)
  - Sidebar (Explorer, Search, Extensions)
  - Activity Bar (left icon bar)
  - Status Bar (bottom bar)
  - Title Bar
  - Tab Bar

- **Adjustable opacity** — Fine-tune transparency from fully transparent (0.0) to fully opaque (1.0) for each section.

- **Glassmorphism blur** — Toggle the frosted-glass `backdrop-filter: blur()` effect globally, with configurable blur intensity per section (0–50px).

- **Optional background wallpaper** — Set a background image URL or file path that shows through the transparent layers.

- **Light & dark theme support** — Automatically adjusts glass tinting for both dark and light VS Code themes.

---

## Installation

### From source (development)

```bash
cd scripts/extension_vs_code_glass

# Install dependencies
npm install

# Compile TypeScript
npm run compile

# Package into a .vsix file
npm run package
```

Then install the `.vsix` file:

1. Open VS Code
2. Press `Ctrl+Shift+P` → **Extensions: Install from VSIX...**
3. Select the generated `.vsix` file

### Quick install (without packaging)

```bash
cd scripts/extension_vs_code_glass
npm install
npm run compile
```

Then create a symlink to your VS Code extensions directory:

```bash
# Linux / WSL
ln -s "$(pwd)" ~/.vscode/extensions/glasscode

# Windows (PowerShell, as Administrator)
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.vscode\extensions\glasscode" -Target "$(Get-Location)"
```

Reload VS Code after linking.

---

## Usage

### Commands

Open the Command Palette (`Ctrl+Shift+P`) and search for:

| Command | Description |
|---------|-------------|
| `GlassCode: Enable Glass Effect` | Apply the glass effect to VS Code |
| `GlassCode: Disable Glass Effect` | Remove the glass effect and restore defaults |
| `GlassCode: Reload Glass Effect` | Re-apply with current settings |
| `GlassCode: Configure Section Transparency` | Interactive picker to configure individual sections |

### Settings

All settings are under the `glassCode.*` namespace in VS Code settings (`Ctrl+,`):

#### Global

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `glassCode.glassmorphism` | boolean | `true` | Enable/disable the blur effect globally |
| `glassCode.backgroundImage` | string | `""` | Background wallpaper URL or file path |
| `glassCode.backgroundOpacity` | number | `0.15` | Wallpaper opacity (0.0–1.0) |

#### Per Section (replace `{section}` with: `editor`, `panel`, `sidebar`, `activityBar`, `statusBar`, `titleBar`, `tabBar`)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `glassCode.{section}.enabled` | boolean | varies | Enable glass for this section |
| `glassCode.{section}.opacity` | number | 0.78–0.90 | Background opacity |
| `glassCode.{section}.blur` | number | 6–14 | Blur radius in pixels |

### Example Configuration

```jsonc
// settings.json
{
  "glassCode.glassmorphism": true,

  // Strong glass effect on editor
  "glassCode.editor.enabled": true,
  "glassCode.editor.opacity": 0.75,
  "glassCode.editor.blur": 16,

  // Frosted terminal panel
  "glassCode.panel.enabled": true,
  "glassCode.panel.opacity": 0.70,
  "glassCode.panel.blur": 20,

  // Subtle sidebar
  "glassCode.sidebar.enabled": true,
  "glassCode.sidebar.opacity": 0.85,
  "glassCode.sidebar.blur": 8,

  // Background wallpaper
  "glassCode.backgroundImage": "https://example.com/wallpaper.jpg",
  "glassCode.backgroundOpacity": 0.12
}
```

---

## How It Works

1. **CSS Injection** — The extension locates VS Code's internal `workbench.html` file (Electron sandbox) and injects a `<style>` block with the generated glassmorphism CSS.

2. **Backup** — On first injection, a backup of the original file is created (`.glasscode-backup`). The `Disable` command restores from this backup.

3. **Reload Required** — After enabling/disabling/reloading the glass effect, VS Code must be reloaded (the extension will prompt you).

4. **"[Unsupported]" Label** — After injection, VS Code shows `[Unsupported]` in the title bar. This is cosmetic and harmless — it simply indicates that core files have been modified.

---

## Important Notes

- **Administrator/sudo may be required** — The extension modifies files in VS Code's installation directory, which may require elevated permissions.
  - **Windows**: Run VS Code as Administrator
  - **Linux/macOS**: You may need to adjust file permissions or run with `sudo`

- **VS Code updates** — Updates may overwrite the injected CSS. Simply run `GlassCode: Enable` again after updating.

- **Performance** — `backdrop-filter` with large blur values can impact rendering performance on lower-end hardware. Start with blur values around 8–12px.

---

## Architecture

```
scripts/extension_vs_code_glass/
├── package.json           # Extension manifest & configuration schema
├── tsconfig.json          # TypeScript compiler options
├── .vscodeignore          # Files excluded from .vsix package
├── README.md              # This file
└── src/
    ├── extension.ts       # Entry point — command & lifecycle management
    ├── injector.ts        # CSS injection engine (workbench.html modification)
    └── styles.ts          # Glassmorphism CSS generator from user config
```

---

## License

MIT
