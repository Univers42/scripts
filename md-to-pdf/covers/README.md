# Cover Templates

Drop-in cover styles for `md-to-pdf`. Each `.css` file is a self-contained
cover page design with its own `:root` tokens and layout rules.

## Available Styles

| Name         | Vibe                                                      |
|--------------|-----------------------------------------------------------|
| `noir`       | Dark gradients, blue glows — Apple keynote energy         |
| `minimal`    | Clean white, thin rules — Dieter Rams "less but better"   |
| `gradient`   | Indigo-to-violet gradient with amber accents              |
| `editorial`  | Warm ivory with left accent stripe — printed journal feel |
| `geometric`  | Dark canvas, dot-grid, rotated wireframes, node glows     |

## Usage

```bash
# Pick a cover by name (no extension needed)
python3 md-to-pdf.py README.md --cover noir
python3 md-to-pdf.py README.md --cover editorial

# List all available covers
python3 md-to-pdf.py --list-covers

# Skip the cover entirely
python3 md-to-pdf.py README.md --no-cover
```

## Creating Your Own

1. Copy any `.css` file in this folder → `my-cover.css`
2. Edit the `:root { … }` tokens — every visual property is a token
3. Run: `python3 md-to-pdf.py README.md --cover my-cover`

### Token Reference

Every cover file uses the same token names. Override what you need:

| Token                       | What it controls                        |
|-----------------------------|-----------------------------------------|
| `--cover-bg`                | Background (color or gradient)          |
| `--cover-fg`                | Primary text color                      |
| `--cover-accent`            | Accent for eyebrow, rules, badges       |
| `--cover-muted`             | Secondary text (subtitle, metadata)     |
| `--cover-glow` / `glow2`   | Decorative radial gradients             |
| `--cover-title-size`        | Main title font size                    |
| `--cover-title-weight`      | Main title font weight                  |
| `--cover-rule-width/height` | Accent rule dimensions                  |
| `--cover-badge-*`           | Top-right pill badge                    |
| `--cover-meta-*`            | Author / date metadata rows             |
| `--cover-foot-*`            | Footer bar                              |

See any `.css` file for the full list (~50 tokens).

### HTML Structure

All cover styles target the same HTML skeleton:

```
.cover
├── .cover-header
│   ├── .brand-logo
│   └── .doc-badge
├── .cover-body
│   ├── .cover-eyebrow
│   ├── h1.cover-h1
│   │   └── .cover-title-accent
│   ├── .cover-sub
│   ├── .cover-rule
│   └── .cover-meta
│       └── .meta-row > .meta-k + .meta-v
└── .cover-foot
    ├── .cover-foot-text
    └── .cover-foot-dots
```
