# md-to-pdf

A self-contained **Markdown → PDF** converter that produces professional,
print-ready documents with automatic table of contents, Mermaid diagrams,
customisable cover pages, and Obsidian-style callout blocks — all driven by
CSS design tokens you can override in seconds.

---

## Table of Contents

- [Quick Start (Python venv)](#quick-start-python-venv)
- [Quick Start (Docker)](#quick-start-docker)
- [Usage](#usage)
- [CLI Reference](#cli-reference)
- [Cover Pages](#cover-pages)
- [Callouts / Admonitions](#callouts--admonitions)
- [Theming](#theming)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)

---

## Quick Start (Python venv)

> **This is by far the easiest and fastest way to get started.**
> If you already have Python 3.10+, you can be converting in under a minute.
> No Docker, no Node, no global installs — just a clean venv.

### 1 — Create a virtual environment

```bash
cd scripts/md-to-pdf/

# Create the venv (only once)
python3 -m venv .venv-pdf

# Activate it
source .venv-pdf/bin/activate        # Linux / macOS
# .venv-pdf\Scripts\activate         # Windows PowerShell
```

### 2 — Install dependencies

```bash
pip install -U pip
pip install markdown pymdown-extensions pygments weasyprint requests
```

> [!info] WeasyPrint system libraries
> WeasyPrint needs **pango** and **cairo** at the OS level.
> On most systems they are already installed. If you get errors about
> missing libraries, install them:
>
> ```bash
> # Debian / Ubuntu
> sudo apt-get install -y libpango-1.0-0 libpangocairo-1.0-0 \
>   libgdk-pixbuf-2.0-0 libcairo2 fonts-dejavu-core fonts-liberation
>
> # macOS (Homebrew)
> brew install pango cairo gdk-pixbuf
>
> # Fedora / RHEL
> sudo dnf install pango cairo gdk-pixbuf2
> ```

### 3 — Convert!

```bash
python3 md-to-pdf.py ../../README.md

# With options
python3 md-to-pdf.py ../../README.md output.pdf \
  --author "Your Name" \
  --cover editorial
```

### 4 — Deactivate when done

```bash
deactivate
```

> [!tip] Why a venv?
> A virtual environment keeps the PDF dependencies **completely isolated**
> from your system Python. No version conflicts, no `sudo pip`, no
> breakage. It's the safest and simplest approach — always prefer it.

---

## Quick Start (Docker)

If you don't want to install Python or any system libraries at all, use
the provided **Dockerfile**. Everything is pre-packaged inside the
container — zero setup on the host.

### 1 — Build the image (once)

```bash
docker build -t md-to-pdf scripts/md-to-pdf/
```

### 2 — Convert

Mount your project root as `/data` so the converter can read your markdown
and write the PDF back to your host filesystem:

```bash
# Basic
docker run --rm -v "$(pwd):/data" md-to-pdf README.md

# With options
docker run --rm -v "$(pwd):/data" md-to-pdf \
  README.md output.pdf \
  --author "Your Name" \
  --cover gradient

# List available covers
docker run --rm md-to-pdf --list-covers
```

> [!info] Paths inside Docker
> All file paths in the command are **relative to `/data`** (your project
> root). So `README.md` means `$(pwd)/README.md` on the host.

### Optional: shell alias

Add this to your `~/.bashrc` or `~/.zshrc` for convenience:

```bash
alias md2pdf='docker run --rm -v "$(pwd):/data" md-to-pdf'
```

Then just:

```bash
md2pdf README.md --cover noir --author "dlesieur"
```

---

## Usage

### Using `convert.sh` (auto-selects engine)

The wrapper script detects whether you have the Python or Node engine
installed and picks the best one automatically:

```bash
./scripts/md-to-pdf/convert.sh README.md
./scripts/md-to-pdf/convert.sh README.md output.pdf --author "Name"
./scripts/md-to-pdf/convert.sh README.md --engine python   # Force engine
```

### Using `setup-pdf.sh` (one-time install)

If you don't want to create the venv manually, the setup script does
everything for you — including system dependencies:

```bash
bash scripts/md-to-pdf/setup-pdf.sh               # Install both engines
bash scripts/md-to-pdf/setup-pdf.sh --python-only  # Python only
bash scripts/md-to-pdf/setup-pdf.sh --node-only    # Node only
```

### Direct invocation

```bash
# Python engine (WeasyPrint — Mermaid via Kroki API)
source .venv-pdf/bin/activate
python3 md-to-pdf.py input.md output.pdf

# Node engine (Puppeteer — Mermaid rendered natively)
node md-to-pdf.mjs input.md output.pdf
```

---

## CLI Reference

```
python3 md-to-pdf.py <input.md> [output.pdf] [options]
```

| Flag               | Description                                                          |
| ------------------ | -------------------------------------------------------------------- |
| `--title "..."`    | Override the document title (default: first `# heading`)             |
| `--subtitle "..."` | Override the subtitle (default: first `*italic*` after title)        |
| `--author "..."`   | Author name displayed on the cover page                              |
| `--theme path.css` | Path to a custom content theme CSS (default: `theme.css`)            |
| `--cover name`     | Cover style: `noir`, `minimal`, `gradient`, `editorial`, `geometric` |
| `--list-covers`    | List all available cover styles and exit                             |
| `--no-cover`       | Skip the cover page entirely                                         |
| `--no-cache`       | Force re-render all Mermaid diagrams (clear cache)                   |

### Examples

```bash
# Minimal — just convert
python3 md-to-pdf.py README.md

# Full options
python3 md-to-pdf.py README.md docs/output.pdf \
  --title "My Project" \
  --subtitle "Architecture Guide" \
  --author "Jane Doe" \
  --cover geometric \
  --theme my-theme.css

# List covers
python3 md-to-pdf.py --list-covers

# No cover, force fresh diagrams
python3 md-to-pdf.py README.md --no-cover --no-cache
```

---

## Cover Pages

Five built-in cover styles are included. Pass any name with `--cover`:

| Name               | Vibe                                                      |
| ------------------ | --------------------------------------------------------- |
| `noir` _(default)_ | Dark gradients, blue glows — Apple keynote energy         |
| `minimal`          | Clean white, thin rules — Dieter Rams "less but better"   |
| `gradient`         | Indigo-to-violet gradient with amber accents              |
| `editorial`        | Warm ivory with left accent stripe — printed journal feel |
| `geometric`        | Dark canvas, dot-grid, rotated wireframes, node glows     |

### Create your own cover

1. Copy any file in `covers/` → `covers/my-cover.css`
2. Edit the `:root { … }` tokens (~50 of them — every visual property)
3. Run: `python3 md-to-pdf.py README.md --cover my-cover`

See [`covers/README.md`](covers/README.md) for the full token reference and
HTML structure.

---

## Callouts / Admonitions

Write **Obsidian-style callouts** directly in your markdown. They are
automatically converted to styled, colour-coded blocks in the PDF.

### Syntax

```markdown
> [!type] Optional custom title
> Body content — supports **bold**, `code`, lists, etc.
> Can span multiple lines.
```

If you omit the title, a sensible default is used (e.g. `[!warning]` →
**"Warning ⚠️"**).

### Supported types

| Type       | Emoji | Colour    | Aliases                    |
| ---------- | ----- | --------- | -------------------------- |
| `note`     | 📝    | Grey      | —                          |
| `info`     | ℹ️    | Blue      | —                          |
| `tip`      | 💡    | Teal      | —                          |
| `success`  | ✅    | Green     | `check`, `done`            |
| `warning`  | ⚠️    | Amber     | `caution`, `attention`     |
| `danger`   | 🔴    | Red       | `error`, `failure`, `fail` |
| `bug`      | 🐛    | Magenta   | —                          |
| `example`  | 📎    | Indigo    | —                          |
| `quote`    | 💬    | Warm grey | `cite`                     |
| `question` | ❓    | Orange    | `help`, `faq`              |
| `abstract` | 📋    | Blue-grey | `summary`, `tldr`          |
| `todo`     | ☑️    | Green     | —                          |

### Live examples

```markdown
> [!tip] Pro tip
> Use `--cover geometric` for a techy look.

> [!warning]
> This will overwrite existing files without confirmation.

> [!danger] Breaking change
> The API has changed in v2. Update your calls.

> [!info] Did you know?
> You can nest **bold** and `code` inside callouts.

> [!bug] Known issue #42
> Mermaid diagrams inside callouts are not yet supported.
```

### Customising callout styles

Every callout property is driven by `:root` CSS tokens in `theme.css`.
Override them to change colours, shapes, backgrounds, or even emoji.

#### Global shape tokens

These control the appearance of **all** callout types at once:

| Token                    | Default     | Description                |
| ------------------------ | ----------- | -------------------------- |
| `--callout-radius`       | `8px`       | Corner radius (right side) |
| `--callout-border-width` | `3px`       | Left border thickness      |
| `--callout-padding`      | `16px 20px` | Inner padding              |
| `--callout-margin`       | `20px 0`    | Outer margin               |
| `--callout-font-size`    | `9.5pt`     | Body text size             |
| `--callout-line-height`  | `1.65`      | Body line height           |
| `--callout-title-weight` | `600`       | Title font weight          |
| `--callout-title-size`   | `10pt`      | Title font size            |
| `--callout-icon-size`    | `1.15em`    | Emoji / icon size          |
| `--callout-header-gap`   | `8px`       | Gap between icon and title |

#### Per-type colour tokens

Each type has four tokens. Replace `{type}` with any of the 12 type
names (`note`, `info`, `tip`, `success`, `warning`, `danger`, `bug`,
`example`, `quote`, `question`, `abstract`, `todo`):

| Token                     | Controls                                    |
| ------------------------- | ------------------------------------------- |
| `--callout-{type}-border` | Left border colour                          |
| `--callout-{type}-bg`     | Background colour                           |
| `--callout-{type}-color`  | Icon & title text colour                    |
| `--callout-{type}-emoji`  | Default emoji (CSS content, for future use) |

#### Example override

```css
:root {
  /* Make all callouts rounder and bigger */
  --callout-radius: 12px;
  --callout-border-width: 4px;
  --callout-padding: 20px 24px;
  --callout-title-size: 11pt;

  /* Make warnings more aggressive */
  --callout-warning-border: #e65100;
  --callout-warning-bg: rgba(230, 81, 0, 0.12);
  --callout-warning-color: #bf360c;

  /* Turn "info" into a purple style */
  --callout-info-border: #7c3aed;
  --callout-info-bg: rgba(124, 58, 237, 0.06);
  --callout-info-color: #6d28d9;
}
```

---

## Theming

The entire visual appearance is controlled by `:root` CSS custom properties
in `theme.css`. To customise:

1. Copy `theme.css` → `my-theme.css`
2. Edit the `:root` tokens (you only need to override what you want to change)
3. Run: `python3 md-to-pdf.py README.md --theme my-theme.css`

### Token categories

| Section            | Key tokens                                                                                     |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| **Base palette**   | `--ink`, `--mid`, `--muted`, `--surface`, `--border`, `--bg`                                   |
| **Accent palette** | `--accent`, `--accent-hover`, `--accent-soft`, `--danger`                                      |
| **Typography**     | `--font-body`, `--font-mono`, `--body-size`, `--h1-size` … `--h4-size`                         |
| **Spacing**        | `--sp-1` (4px) through `--sp-16` (64px)                                                        |
| **Radius**         | `--radius-sm` (4px), `--radius-md` (8px), `--radius-lg` (12px), `--radius-pill`                |
| **Page geometry**  | `--page-size`, `--page-margin-v`, `--page-margin-h`                                            |
| **Code blocks**    | `--code-bg`, `--code-fg`, `--code-inline-bg`, `--code-radius`                                  |
| **Tables**         | `--table-header-bg`, `--table-stripe-bg`, `--table-radius`, `--table-cell-pad`                 |
| **Blockquotes**    | `--bq-bg`, `--bq-border`, `--bq-radius`, `--bq-padding`                                        |
| **Links**          | `--link-color`, `--link-hover-bg`, `--link-hover-color`, `--link-hover-decoration`             |
| **Callouts**       | `--callout-radius`, `--callout-{type}-border`, `--callout-{type}-bg`, `--callout-{type}-color` |
| **Selection**      | `--selection-bg`, `--selection-color`                                                          |
| **TOC**            | `--toc-title-size`, `--toc-h2-size`, `--toc-border`                                            |
| **HR**             | `--hr-color`, `--hr-thickness`, `--hr-margin`                                                  |
| **Diagrams**       | `--diagram-margin`, `--diagram-max-h`                                                          |

---

## Project Structure

```
scripts/md-to-pdf/
├── md-to-pdf.py          # Python engine (WeasyPrint + Kroki)
├── md-to-pdf.mjs         # Node engine (Puppeteer + Marked)
├── convert.sh            # Smart wrapper — auto-selects engine
├── setup-pdf.sh          # One-time dependency installer
├── theme.css             # Content theme (all :root tokens)
├── Dockerfile            # Containerised build
├── .dockerignore
├── README.md             # ← You are here
├── covers/
│   ├── README.md         # Cover token reference
│   ├── noir.css          # Dark gradients (default)
│   ├── minimal.css       # Clean white
│   ├── gradient.css      # Indigo-to-violet
│   ├── editorial.css     # Warm ivory journal
│   └── geometric.css     # Dark wireframe canvas
└── .mermaid-cache/       # Auto-created PNG cache for diagrams
```

---

## Troubleshooting

### "No module named weasyprint" / "No module named markdown"

You forgot to activate the virtual environment, or the dependencies are
not installed yet:

```bash
source .venv-pdf/bin/activate
pip install markdown pymdown-extensions pygments weasyprint requests
```

### "cannot load library 'libpango'" / "cairo not found"

WeasyPrint needs system-level libraries. Install them:

```bash
# Debian / Ubuntu
sudo apt-get install -y \
  libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 \
  libgdk-pixbuf-2.0-0 libcairo2

# macOS
brew install pango cairo gdk-pixbuf

# Fedora
sudo dnf install pango cairo gdk-pixbuf2
```

Or just **use Docker** — zero system deps:

```bash
docker build -t md-to-pdf scripts/md-to-pdf/
docker run --rm -v "$(pwd):/data" md-to-pdf README.md
```

### "Mermaid diagram failed / all attempts failed"

The Python engine renders Mermaid diagrams via the
[Kroki.io](https://kroki.io) API. If you're offline or the API is down,
diagrams fall back to a code block.

- Check your internet connection
- Try `--no-cache` to force a fresh render
- Use the Node engine (`--engine node`) which renders Mermaid locally

### "No PDF engine found!"

Neither engine is installed. Run the setup script:

```bash
bash scripts/md-to-pdf/setup-pdf.sh
```

Or install manually with a venv (recommended):

```bash
python3 -m venv .venv-pdf
source .venv-pdf/bin/activate
pip install markdown pymdown-extensions pygments weasyprint requests
```

### PDF looks different on different machines

Font rendering depends on installed system fonts. For consistent output:

- Install the recommended fonts: `fonts-dejavu-core`, `fonts-liberation`
- Or use Docker — it bundles the exact same fonts every time

### Callouts showing as raw `> [!type]`

Make sure you're using the **Python engine** (`md-to-pdf.py`). The callout
preprocessor runs before markdown conversion. The Node engine
(`md-to-pdf.mjs`) does not yet support callouts.

---

## License

MIT — see the project root for details.
