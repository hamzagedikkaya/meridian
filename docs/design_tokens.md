# Design Tokens Reference

All tokens are declared in [`app/assets/tailwind/application.css`](../app/assets/tailwind/application.css) inside `@theme` (dark) and `html.light` (light overrides).

## Typography

| Token | Value | Use |
|-------|-------|-----|
| `--font-display` | Fraunces, variable | Headings, hero numbers |
| `--font-sans` | DM Sans | Body, UI |
| `--font-mono` | JetBrains Mono | Code, schema versions |

## Color (dark — default)

| Token | Hex | Purpose |
|-------|-----|---------|
| `--color-bg-base` | `#0A0908` | Page background |
| `--color-bg-elevated` | `#161514` | Cards |
| `--color-bg-overlay` | `#1F1D1B` | Modals, dropdowns |
| `--color-bg-hover` | `#1A1817` | Hover state |
| `--color-fg-primary` | `#F5F1E8` | Body text |
| `--color-fg-muted` | `#A09B8E` | Secondary text |
| `--color-fg-faint` | `#5E574D` | Disabled / helper |
| `--color-accent-500` | `#B8860B` | Primary CTAs, links |
| `--color-income` | `#6B8E5A` | Positive amounts |
| `--color-expense` | `#B85450` | Negative amounts |
| `--color-warning` | `#D4915A` | Warnings |
| `--color-info` | `#6B8FA0` | Info badges |

Light mode inverts backgrounds and foregrounds but keeps the accent palette.

## Radii

`--radius-xs 6px`, `--radius-sm 8px`, `--radius-md 12px`, `--radius-lg 20px`, `--radius-xl 28px`.

## Component classes

`.card`, `.stat-number`, `.pill` — composed of utility classes for reuse across modules.
