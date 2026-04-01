---
name: ui-designer
description: "Front-end UI/UX designer for TKR Studios Shiny app. Use when: designing or redesigning any module's UI, improving layout aesthetics, adding interactive graphics, fixing colliding/overlapping elements, applying the design token system, improving navigation flow, creating a new page or panel from scratch, ensuring the cockpit principle (one-click access to primary actions), choosing colors or typography, adding day/night theming. Produces polished, accessible, screen-adaptive Shiny UI with pleasant color themes and professional information hierarchy."
argument-hint: "Describe the UI task: module name, what to design/fix, screen size target, and any brand or tone notes (e.g. 'redesign module_export.R sidebar — modern, dark, desktop-first')"
---

# UI/UX Designer — TKR Studios

Produces modern, elegant, responsive Shiny UI that feels like a professional creative tool — not a data dashboard. Every design decision follows the **Cockpit Principle**: everything the user needs is visible and reachable in one action, with no hunting.

---

## Core Philosophy

| Principle | Meaning in Practice |
|---|---|
| **Cockpit** | Primary actions always visible — never buried in menus. Secondary actions in context panels that appear on demand. |
| **One-click access** | Any frequently-used feature reachable from any screen in ≤ 1 click. |
| **Context-aware** | Show the right controls for what the user is currently doing. Hide irrelevant controls. |
| **Well-connected** | Navigation between all sections is always reachable from the top utility bar — no dead ends. |
| **No collision** | Elements never overlap unless intentionally layered (modals, tooltips). Every element has breathing room. |
| **Pleasant but professional** | Colours evoke creativity (modern studio feel) without being garish. Dark surfaces for creative tools; light surfaces for data/forms. |

---

## Design Token System (use these — never magic numbers)

All tokens live in `R/mobile_responsive.R` → `get_responsive_css()` `:root {}` block.

### Spacing
```css
--sp-2   /* 2–4px   — icon gap, tight padding */
--sp-4   /* 4–8px   — button inner padding supplement */
--sp-8   /* 6–12px  — standard component padding */
--sp-12  /* 10–16px — card padding, list item padding */
--sp-16  /* 12–20px — panel padding */
--sp-24  /* 16–28px — section gaps, hero padding */
```

### Typography — fluid, auto-adjusts with viewport
```css
--text-xs   /* 10–11px — badges, technical labels */
--text-sm   /* 11–13px — secondary labels, helper text */
--text-md   /* 13–15px — body text, form labels */
--text-lg   /* 15–18px — panel headings, important labels */
--text-xl   /* 18–24px — section titles, feature headings */
```
**Rule:** Always use `font-size: var(--text-md)` etc. — never `font-size: 14px` directly.

### Border Radius
```css
--r-sm   /* 6px  — small chips, tags, badges */
--r-md   /* 10px — buttons, inputs, small cards */
--r-lg   /* 18px — panels, drawers, tool panes */
--r-xl   /* 26px — bottom sheets, large modals */
```

### Colour Palette (TKR Studios dark studio theme)
See full palette in [assets/design-tokens.md](./assets/design-tokens.md).

Core semantic colours (use CSS vars — never raw hex):
```css
var(--primary, #5b6af0)      /* Brand indigo — CTAs, active states */
var(--primary-hover, #4a58d6) /* Darker primary for :hover */
var(--success, #22c55e)       /* Confirmations, saved state */
var(--warning, #f59e0b)       /* Alerts, in-progress */
var(--danger, #ef4444)        /* Destructive actions, errors */
var(--surface, #1e2130)       /* Panel backgrounds (dark) */
var(--surface-2, #252839)     /* Secondary panels, sidebar */
var(--border, #334155)        /* Dividers, input borders */
var(--text, #f1f5f9)          /* Primary text on dark bg */
var(--text-muted, #94a3b8)    /* Secondary labels, placeholders */
```

### Transitions
```css
var(--ease-out,    cubic-bezier(.2, 0, .0, 1))   /* Standard slide/fade */
var(--ease-spring, cubic-bezier(.34, 1.35, .64, 1)) /* Bouncy open/close */
```
Every interactive element should have `transition: 0.15s var(--ease-out)` on `background`, `color`, `border-color`, `box-shadow`.

---

## Shiny Component Decision Tree

See [assets/shiny-ui-patterns.md](./assets/shiny-ui-patterns.md) for full patterns. Quick guide:

| User Need | Shiny Component | Notes |
|---|---|---|
| Primary action | `actionButton` with icon + label | Always visible, never inside a collapsed section |
| Destructive action | `actionButton` + `shinyalert`/`modalDialog` confirm | Never single-click delete |
| Settings / options | `sidebarPanel` or collapsible `wellPanel` | Pull-out drawer on mobile |
| Data input form | `modalDialog` | Don't embed forms in sidebars unless very short |
| Status / feedback | `showNotification` (temp) or inline status badge | Duration ≤ 3s for success; error stays until dismissed |
| Progress | `withProgress` / `incProgress` | Always show for ops > 500ms |
| Navigation | `tabPanel` inside `navbarPage` or `shinydashboard` `menuItem` | Max 7 tabs; group by task not feature |
| Contextual help | `tipify()` (shinyBS tooltip) or `title=` attribute | Right-align tooltips on far-left elements |
| File picker | `fileInput` | Custom-styled: hide browser native button, show custom one |

---

## Layout Patterns

### 1. The Cockpit Layout (used in module_editor.R)
```
┌─────────────────────────────────────────────────────────┐
│  TOP HANDLE: breadcrumb · page nav · zoom · actions     │  ← Always visible
├────────┬────────────────────────────────┬───────────────┤
│  LEFT  │                                │  RIGHT        │
│ DRAWER │      CANVAS / MAIN VIEW        │ DRAWER        │  ← Drawers overlay; don't push
│ (tool  │                                │ (properties/  │
│  panel)│                                │  context)     │
├────────┴────────────────────────────────┴───────────────┤
│  BOTTOM HANDLE: status · filmstrip · secondary actions  │  ← Always visible
└─────────────────────────────────────────────────────────┘
```
- Left drawer: **tools** (what you do)
- Right drawer: **properties** (how you do it — context-sensitive to selection)
- Centre: **content** — never cluttered with controls

### 2. The Studio Panel (used in AI editor, analytics)
```
┌──────────────────────┬──────────────────────────────────┐
│  CONTROL PANEL       │  PREVIEW / OUTPUT                │
│  (inputs, sliders,   │  (large, dominant, always full   │
│   options — 35%)     │   height — 65%)                  │
└──────────────────────┴──────────────────────────────────┘
```
- On mobile (< 768px): stack vertically, preview first, controls beneath as accordions.

### 3. The Utility Bar Popover (used in language, settings, cloud)
```
HEADER  [🌐 English ▾] [☁ Cloud ▾] [📊 Analytics ▾] [⚙ Settings ▾]
```
- Each item is a dropdown or slide-down panel anchored to its button
- Never opens a new page — always inline or overlay
- Close on outside-click

---

## Step-by-Step Design Procedure

### Step 1 — Understand the user task
Before touching any file, answer:
1. What is the user *trying to accomplish* in this screen?
2. What is their **primary action** (the one thing they do most)?
3. What is contextual (only relevant after they've done something)?
4. What is administrative (settings, rarely needed)?

Primary → cockpit / always visible.  
Contextual → right drawer or inline panel that appears on selection.  
Administrative → utility bar popover or settings tab.

### Step 2 — Audit for collisions and overlap
```r
# Read the target module's UI function
# Look for: fixed pixel widths, absolute positioning, missing min-width/max-width
# Check: does it have a mobile CSS override?
```
Run through the [assets/ui-audit-checklist.md](./assets/ui-audit-checklist.md) before writing new CSS.

### Step 3 — Apply the token system
Replace all magic numbers:
- `14px` → `var(--text-md)`
- `8px` spacing → `var(--sp-8)`
- `border-radius: 4px` → `var(--r-sm)`
- Raw `#5b6af0` → `var(--primary)`

### Step 4 — Typography hierarchy
```
Page title       : --text-xl, font-weight 700, var(--text)
Section heading  : --text-lg, font-weight 600, var(--text)
Sub-heading      : --text-md, font-weight 600, var(--text)
Body / label     : --text-md, font-weight 400, var(--text)
Helper / hint    : --text-sm, font-weight 400, var(--text-muted)
Badge / chip     : --text-xs, font-weight 600, uppercase, letter-spacing 0.5px
```

### Step 5 — Interaction states (every interactive element needs all 4)
```css
.my-btn                    { background: var(--primary); transition: 0.15s var(--ease-out); }
.my-btn:hover              { background: var(--primary-hover); }
.my-btn:active             { transform: scale(0.97); }
.my-btn:focus-visible      { outline: 2px solid var(--primary); outline-offset: 3px; }
.my-btn:disabled,
.my-btn[disabled]          { opacity: 0.45; pointer-events: none; }
```

### Step 6 — Verify at 3 breakpoints
Test the layout mentally (or with DevTools) at:
- **375px** (iPhone SE) — single column, 44px tap targets
- **768px** (iPad portrait) — two columns max, drawers as overlays
- **1440px** (desktop) — full cockpit with all panels visible

Use the breakpoints from `R/mobile_responsive.R`:
- `≤480px` — phone portrait
- `481–768px` — small tablet / phone landscape
- `769–1024px` — large tablet
- `≥1025px` — desktop

### Step 7 — Interactive graphics checklist
- SVGs: use `currentColor` for strokes/fills → auto-adapts to dark/light
- Charts: use the Okabe-Ito palette (colour-blind safe): `#E69F00 #56B4E9 #009E73 #F0E442 #0072B2 #D55E00 #CC79A7`
- Animated transitions: `@prefers-reduced-motion: reduce` block that disables animations
- Canvas elements: `touch-action: none` to hand to Pointer Events API

---

## Quality Gate Checklist

Before marking any UI task complete:

- [ ] All sizes use design tokens (no magic pixel values)
- [ ] All colours use CSS variables (no raw hex)
- [ ] Typography follows the 5-level hierarchy above
- [ ] Interactive elements have all 4 states (default/hover/active/focus)
- [ ] No elements overlap or collide at any of the 3 breakpoints
- [ ] Primary action is visible without scrolling on desktop
- [ ] Touch targets ≥ 44×44px on mobile
- [ ] `transition:` on all interactive elements
- [ ] Day/night contrast passes 4.5:1 for body text (WCAG AA)
- [ ] `aria-label` or `title` on all icon-only buttons
- [ ] `@media (prefers-reduced-motion: reduce)` disables animations
