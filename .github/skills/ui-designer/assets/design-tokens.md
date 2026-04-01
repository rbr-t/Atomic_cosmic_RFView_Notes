# TKR Studios — Design Tokens Reference

All tokens defined in `R/mobile_responsive.R` → `get_responsive_css()`.

---

## Spacing Scale

| Token | Range | Use |
|---|---|---|
| `--sp-2`  | 2–4px   | Icon gap, tight inline padding |
| `--sp-4`  | 4–8px   | Button padding supplement, badge padding |
| `--sp-8`  | 6–12px  | Standard component padding, list item gap |
| `--sp-12` | 10–16px | Card padding, section inner padding |
| `--sp-16` | 12–20px | Panel padding, form field gap |
| `--sp-24` | 16–28px | Section gap, hero padding, drawer padding |

---

## Type Scale

| Token | Range | Use |
|---|---|---|
| `--text-xs` | 10–11px | Badges, timestamps, technical secondary labels |
| `--text-sm` | 11–13px | Helper text, table data, secondary labels |
| `--text-md` | 13–15px | Body copy, form labels, button labels |
| `--text-lg` | 15–18px | Panel headings, card titles |
| `--text-xl` | 18–24px | Page/section titles, feature headers |

---

## Border Radius

| Token | Value | Use |
|---|---|---|
| `--r-sm` | 6px  | Tags, chips, small badges |
| `--r-md` | 10px | Buttons, inputs, small cards |
| `--r-lg` | 18px | Drawers, tool panes, panels |
| `--r-xl` | 26px | Bottom sheets, large modals, feature cards |

---

## Layout

| Token | Value | Use |
|---|---|---|
| `--header-h`     | 50px  | Height of the top navigation bar |
| `--sidebar-full` | 230px | Open sidebar width |
| `--sidebar-mini` | 50px  | Collapsed sidebar icon-only width |

---

## Colour Palette — Dark Studio Theme

### Semantic Colours (always use vars)

| Token | Value | Use |
|---|---|---|
| `--primary`       | `#5b6af0` | Brand indigo — primary CTAs, active states, focus rings |
| `--primary-hover` | `#4a58d6` | Primary button hover |
| `--success`       | `#22c55e` | Saved state, success notification |
| `--warning`       | `#f59e0b` | In-progress, alert, RTL badge |
| `--danger`        | `#ef4444` | Errors, destructive action confirmations |
| `--info`          | `#38bdf8` | Info tooltips, help indicators |

### Surface Hierarchy (layering)

| Layer | Token | Approximate HEX | Use |
|---|---|---|---|
| 0 | `--bg` | `#0f1117` | Page background |
| 1 | `--surface` | `#1e2130` | Primary panel / card background |
| 2 | `--surface-2` | `#252839` | Secondary panels, sidebar |
| 3 | `--surface-3` | `#2e3347` | Hover row, input background |
| — | `--border` | `#334155` | Dividers, input borders, separators |

### Text Colours

| Token | Use |
|---|---|
| `--text`        | Primary text on dark bg |
| `--text-muted`  | Secondary labels, placeholders, breadcrumbs |
| `--text-subtle` | Disabled labels, very quiet hint text |

---

## Transitions

| Token | Curve | Use |
|---|---|---|
| `--ease-out`    | `cubic-bezier(.2, 0, .0, 1)`       | Panels sliding, fades, most UI |
| `--ease-spring` | `cubic-bezier(.34, 1.35, .64, 1)` | Bouncy open/close (tooltips, menus, drawers) |

Standard duration: `0.15s` for micro-interactions, `0.25s` for panels/drawers.

---

## Colour-Blind Safe Chart Palette (Okabe-Ito)

Use for all data visualisations. Safe for deuteranopia, protanopia, and tritanopia:

| Swatch | HEX | Name |
|---|---|---|
| 🟡 | `#E69F00` | Orange |
| 🔵 | `#56B4E9` | Sky Blue |
| 🟢 | `#009E73` | Bluish green |
| 🟡 | `#F0E442` | Yellow |
| 🔷 | `#0072B2` | Blue |
| 🔴 | `#D55E00` | Vermilion |
| 🩷 | `#CC79A7` | Reddish purple |
| ⬛ | `#000000` | Black |
