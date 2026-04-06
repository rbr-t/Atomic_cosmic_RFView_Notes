# Design System: RF PA Design Application

> **Template note:** This file follows the [Stitch DESIGN.md format](https://stitch.withgoogle.com/docs/design-md/format/) as
> popularised by the [awesome-design-md](https://github.com/VoltAgent/awesome-design-md) collection.
> This specification is derived from the actual CSS tokens and app config in this repository.
> AI agents generating UI for this app must read this file first. No hex value, font family,
> or spacing value may be used that is not defined here.

---

## 1. Visual Theme & Atmosphere

This design system is built for **RF engineering instrument interfaces** — expert-user
environments that combine live measurement data, PCB canvas manipulation, AI agent output,
and complex parameter tables on a single screen. The aesthetic is
**oscilloscope-native, instrument-panel dark**: a near-pure-black canvas (`#0b0b0b`)
where component topology, signal graphs, and calculation outputs emerge against dark
panel surfaces. Colour serves as operational signal, not decoration.

The primary accent is **Signal Orange `#ff7f11`** — the colour engineers associate with
selection, activation, and primary action on dark RF test equipment. A secondary accent
of **Measurement Blue `#00aaff`** is used exclusively for multi-selection states and
Smith chart / S-parameter trace overlays. Every other surface is neutral.

The typographic backbone is **Inter Variable** for all Shiny UI text, labels, and
navigation. **JetBrains Mono** is used for all agent output, calculation results,
S-parameter tables, RF values, unit strings, and code blocks — anything emitted by the
calculation engines or AI agents.

**Key Characteristics:**

- Instrument-dark: `#0b0b0b` canvas → `#1a1a1a` panel → `rgba(26,26,26,0.95)` property editor
- One primary accent: Signal Orange `#ff7f11` for selection, active state, primary CTA
- One secondary accent: Measurement Blue `#00aaff` for multi-select and trace overlays
- Glows communicate component state on canvas — not flat border changes
- Status colours (green / amber / red) used only for PASS/WARN/FAIL design validation
- Density-first: 13px base body, compact table rows, tight label spacing
- Inter Variable for UI structure; JetBrains Mono for all numeric and agent output

---

## 2. Color Palette & Roles

### Background Surfaces

| Name | Hex | Role |
| --- | --- | --- |
| Canvas | `#0b0b0b` | PA lineup canvas background, page outermost shell |
| Panel | `#1a1a1a` | Sidebar, modal, property editor, nav background |
| Surface | `rgba(26,26,26,0.95)` | Cards, property editor panels, overlays |
| Raised | `#2a2a2a` | Hover surface, scrollbar track, input backgrounds |
| Frame | `#444444` | Section dividers, property group separators |
| Overlay | `rgba(0,0,0,0.6)` | Modal scrim, tooltip backdrop |

### Text & Content

| Name | Hex | Role |
| --- | --- | --- |
| Primary | `#ffffff` | Headings, section titles, active labels |
| Secondary | `#cccccc` | Body copy, parameter labels, descriptions |
| Muted | `#888888` | Metadata, units, placeholder text |
| Disabled | `#555555` | Inactive controls, unavailable parameters |

### Brand & Accent

| Name | Hex | Role |
| --- | --- | --- |
| Signal Orange | `#ff7f11` | Primary CTA, active selection glow, scrollbar thumb, heading underline, property editor border |
| Orange Muted | `rgba(255,127,17,0.15)` | Toolbar highlight, active nav background |
| Orange Glow | `rgba(255,127,17,0.8)` | Canvas component hover shadow |
| Measurement Blue | `#00aaff` | Multi-select highlight, Smith chart traces, S-parameter overlays |
| Blue Muted | `rgba(0,170,255,0.15)` | Multi-select row background |
| Cyan Highlight | `rgba(0,255,255,0.9)` | Text drag mode, active text placement handles |

### Status & RF Validation Colors

| Name | Hex | Role |
| --- | --- | --- |
| Pass / Healthy | `#22c55e` | Design validation pass, spec compliance PASS |
| Pass Muted | `rgba(34,197,94,0.15)` | Pass badge background |
| Warning / Amber | `#f59e0b` | Spec approaching limit, Ropt < 5Ω advisory |
| Warning Muted | `rgba(245,158,11,0.15)` | Warning badge background |
| Error / Fail | `#ef4444` | Spec breach, design rule violation, agent error |
| Error Muted | `rgba(239,68,68,0.15)` | Error badge background |
| RF Yellow | `#ffff00` | Canvas component warning glow (impedance mismatch, out-of-guardrail) |
| RF Red | `#ff0000` | Canvas component error pulse (invalid component connection) |

### Border & Divider

| Name | Value | Role |
| --- | --- | --- |
| Border Subtle | `rgba(255,255,255,0.07)` | Default card edges, input outlines |
| Border Standard | `rgba(255,255,255,0.12)` | Prominent dividers, focused inputs |
| Border Strong | `rgba(255,255,255,0.18)` | High-contrast separators |
| Border Accent | `2px solid #ff7f11` | Property editor outer border, active panel frame |
| Divider | `1px solid #444` | Property group row separators |

---

## 3. Typography Rules

### Font Families

- **Primary**: `Inter Variable`, fallback: `"SF Pro Display", -apple-system, system-ui, "Segoe UI", Roboto, sans-serif`
- **Monospace**: `"JetBrains Mono"`, fallback: `"Fira Code", "Cascadia Code", ui-monospace, "SF Mono", Menlo, monospace`
- **OpenType Features**: `"cv01", "ss03"` on Inter for geometric alternates and reading clarity

### Hierarchy

| Role | Font | Size | Weight | Line Height | Notes |
| --- | --- | --- | --- | --- | --- |
| Page Title | Inter Variable | 28px | 600 | 1.20 | Main tab headings |
| Section Heading | Inter Variable | 18px | 600 | 1.30 | Card headers, property panel headings |
| Sub-heading | Inter Variable | 16px | 600 | 1.35 | Property group labels, sub-panel titles |
| Body | Inter Variable | 14px | 400 | 1.55 | Standard UI text, descriptions |
| Body Medium | Inter Variable | 14px | 500 | 1.55 | Navigation labels, table column headers |
| Caption | Inter Variable | 12px | 400 | 1.50 | Metadata, timestamps, helper text |
| Label | Inter Variable | 11px | 500 | 1.40 | Uppercase chip labels, section eyebrows |
| RF Value | JetBrains Mono | 14px | 500 | 1.55 | Numeric parameters with units (e.g. `28 V`, `3.5 GHz`) |
| Agent Output | JetBrains Mono | 13px | 400 | 1.65 | All AI agent responses, calculation engine output |
| Code Body | JetBrains Mono | 13px | 400 | 1.65 | Code blocks, S-parameter tables, log output |
| Code Inline | JetBrains Mono | 12px | 400 | 1.50 | Inline parameter references, file paths |
| Canvas Label | Inter Variable | 11px | 500 | 1.20 | Component labels on PA lineup canvas |

### RF-Specific Typography Rules

- **Always render RF engineering values in JetBrains Mono with the unit attached**: `28 V`, `3.5 GHz`, `47.3 dBm`, `62.4 %`. Never strip units.
- **S-parameter notation** (S11, S21, etc.) uses capital letters, no spaces, in monospace.
- **Decibel scale labels** (dBm, dBc, dB) are lowercase 'd', uppercase 'B': `dBm`, not `DBm` or `dbm`.
- **Color headings orange**: property editor section headers use `color: #ff7f11` — consistent with hardware instrument labelling convention.
- **Agent output blocks** must always use JetBrains Mono, never Inter — the monospace typeface is the visual cue that output was generated, not typed.

---

## 4. Component Stylings

### Canvas Component (PA Lineup / RF CAD)

Canvas components are Konva.js objects rendered on a dark `#0b0b0b` stage.

- **Default state**: neutral render, no glow
- **Hover**: `drop-shadow(0 0 5px rgba(255,127,17,0.8))` — orange glow
- **Selected**: `drop-shadow(0 0 8px #ff7f11)` — stronger orange glow
- **Multi-selected**: `drop-shadow(0 0 10px #00aaff)` + `opacity: 0.95` — blue glow
- **Warning**: `drop-shadow(0 0 10px rgba(255,255,0,0.7))` — yellow glow, pulsing
- **Invalid/Error**: `drop-shadow(0 0 12px rgba(255,0,0,0.9))` + `pulse-error` animation — red rapid pulse
- **Text drag**: `drop-shadow(0 0 3px rgba(0,255,255,0.9))` + `pulse-text` animation — cyan slow pulse
- **Canvas background**: `#0b0b0b`, `border-radius: 8px`

### Property Editor Panel

The floating right-side panel that appears when a canvas component is selected.

- Background: `rgba(26,26,26,0.95)`
- Border: `2px solid #ff7f11`
- Radius: `8px`
- Padding: `15px`
- Shadow: `0 4px 20px rgba(0,0,0,0.5)`
- Heading (`h4`): `color: #ff7f11`, 16px weight 600, `border-bottom: 1px solid #444`
- Property group label: `color: #ccc`, 12px weight 500, uppercase
- Input/select: background `#333`, text `#fff`, border `1px solid #555`, radius `4px`

### Buttons

#### Primary Button

- Background: `#ff7f11`
- Text: `#ffffff`, 14px weight 600
- Padding: `8px 16px`
- Radius: `6px`
- Hover: `rgba(255,127,17,0.85)` background
- Use: Run calculation, apply design, invoke agent

#### Secondary Button

- Background: `rgba(255,255,255,0.06)`
- Text: `#ffffff`, 14px weight 500
- Padding: `8px 16px`
- Radius: `6px`
- Border: `1px solid rgba(255,255,255,0.12)`
- Hover: `rgba(255,255,255,0.10)` background
- Use: Cancel, secondary actions, export

#### Destructive Button

- Background: `rgba(239,68,68,0.12)`
- Text: `#ef4444`, 14px weight 600
- Padding: `8px 16px`
- Radius: `6px`
- Border: `1px solid rgba(239,68,68,0.25)`
- Hover: `rgba(239,68,68,0.20)` background
- Use: Delete project, reset canvas, clear design

#### Icon Button

- Background: `rgba(255,255,255,0.04)`
- Icon: `#888888`, 16px
- Padding: `6px`
- Radius: `6px`
- Border: `1px solid rgba(255,255,255,0.07)`
- Hover: `rgba(255,255,255,0.09)` background, icon `#ff7f11`
- **Accessible label required** (`aria-label` or `title`)

### Cards & Containers

- Background: `#1a1a1a`
- Border: `1px solid rgba(255,255,255,0.07)`
- Radius: `8px`
- Padding: `16px` standard, `24px` featured
- Shadow: none (luminance-based hierarchy)
- Active/selected card: border upgrades to `1px solid #ff7f11`

### Inputs & Forms

#### Text Input / Numeric Input

- Background: `#333333`
- Text: `#ffffff`, 14px weight 400
- Placeholder: `#888888`
- Border: `1px solid #555555`
- Radius: `4px`
- Padding: `6px 10px`
- Focus border: `1px solid #ff7f11`
- Focus shadow: `0 0 0 2px rgba(255,127,17,0.20)`
- Error border: `1px solid #ef4444`

#### Select / Dropdown

- Same as Text Input
- Dropdown panel background: `#2a2a2a`

### Badges & Status Chips

| Variant | Background | Text |
| --- | --- | --- |
| Default | `rgba(255,255,255,0.08)` | `#cccccc` |
| Active / Info | `rgba(255,127,17,0.15)` | `#ff7f11` |
| Pass | `rgba(34,197,94,0.15)` | `#22c55e` |
| Warning | `rgba(245,158,11,0.15)` | `#f59e0b` |
| Fail / Error | `rgba(239,68,68,0.15)` | `#ef4444` |
| Multi-select | `rgba(0,170,255,0.15)` | `#00aaff` |

- Radius: `4px` inline, `9999px` standalone pill
- Font: 12px weight 500, Inter Variable
- Padding: `2px 8px` inline, `3px 10px` standalone

### Navigation (Shiny Sidebar)

- Background: `#1a1a1a`
- Brand label: 16px Inter weight 600, `#ff7f11`
- Nav links: 14px weight 500, `#cccccc` default, `#ffffff` hover, `#ff7f11` active
- Active indicator: `2px left border #ff7f11`, background `rgba(255,127,17,0.08)`
- Bottom nav border: `1px solid rgba(255,255,255,0.07)`

### Scrollbars

- Track: `#2a2a2a`
- Thumb: `#ff7f11`
- Width: 6px
- Thumb radius: 3px
- Apply to: component palette, long property panels, log viewers

### Tables (Design Parameter / S-Parameter)

- Header row: `#1a1a1a` background, 11px weight 500 uppercase `#888888`
- Body rows: alternate `#0b0b0b` / `rgba(255,255,255,0.02)` zebra
- Row border: `1px solid rgba(255,255,255,0.05)`
- Hover row: `rgba(255,127,17,0.04)` background
- Primary cell: 13px JetBrains Mono `#ffffff` (RF values)
- Secondary cell: 13px Inter `#cccccc` (labels, descriptions)

### Code Blocks / Agent Output

- Background: `#0b0b0b`
- Border: `1px solid rgba(255,255,255,0.10)`
- Radius: `6px`
- Padding: `12px 16px`
- Font: JetBrains Mono 13px weight 400, `#cccccc`
- Language/agent label: 11px Inter weight 500 uppercase `#888888` top-right
- Scrollable horizontally on overflow

---

## 5. Layout Principles

### Spacing System

Base unit: **8px**

| Token | Value | Use |
| --- | --- | --- |
| space-1 | 4px | Icon gap, dense item spacing |
| space-2 | 8px | Inner padding, label gap |
| space-3 | 12px | Input padding, tight card inner |
| space-4 | 16px | Standard card padding, section gap |
| space-6 | 24px | Component separation |
| space-8 | 32px | Section separation |
| space-12 | 48px | Major section gaps |

### Grid & Container

- **Shiny sidebar**: 250px fixed, collapsible
- **Main content**: fluid, min-width 960px desktop
- **PA Lineup canvas**: `height: 600px`, full available width within tab
- **Dashboard grid**: 6 main design-flow tabs (System → Stage → Transistor → Topology → Simulation → Report)
- **Chart panels**: full-width within card, min-height 350px for plotly charts

### PA Lineup Canvas Layout

- Container: `position: relative`, `width: 100%`, `height: 600px`, `background: #0b0b0b`, `border-radius: 8px`
- Component palette: `position: absolute`, left-anchored, `overflow-y: auto`, custom scrollbar
- Property editor: floating panel triggered by component selection, right-side anchored
- Toolbar: thin strip above canvas, icon buttons only

### Whitespace Philosophy

- **Black as instrument space**: the near-pure-black canvas acts as the instrument panel. Tight component padding is right — the canvas itself provides macro breathing room.
- **Pack RF values, separate sections**: RF tables are dense by design. Use generous gaps (24px+) between card sections, not inside them.
- **Glow as affordance**: on the canvas, state (hover/select/error) is communicated via glow, not via border changes or background shifts.

### Border Radius Scale

| Name | Value | Use |
| --- | --- | --- |
| Sharp | 2px | Tags, micro badges |
| Subtle | 4px | Input fields, small buttons, property inputs |
| Standard | 6px | Buttons, dropdowns |
| Card | 8px | Cards, panels, canvas container, property editor |
| Full Pill | 9999px | Status pills, agent confidence chips |

---

## 6. Depth & Elevation

| Level | Treatment | Use |
| --- | --- | --- |
| Flat (0) | `#0b0b0b` | Canvas stage, page outermost shell |
| Surface (1) | `#1a1a1a` + border `rgba(255,255,255,0.07)` | Sidebar, nav, card containers |
| Raised (2) | `rgba(26,26,26,0.95)` + border `rgba(255,255,255,0.09)` | Property editor, dropdowns, modals |
| Elevated (3) | `#2a2a2a` + border `rgba(255,255,255,0.12)` | Hovered rows, tooltips, active inputs |
| Focus ring | `0 0 0 2px rgba(255,127,17,0.20)` | Keyboard focus on all interactive elements |
| Canvas glow | `drop-shadow(0 0 8px #ff7f11)` | Canvas component selection — not elevation, but state |

Avoid traditional drop shadows on panel surfaces — dark-on-dark shadows add noise without benefit. Use background luminance stepping for depth, and reserve glow effects strictly for the canvas interaction layer.

---

## 7. Do's and Don'ts

### Do

- Set `font-feature-settings: "cv01", "ss03"` on all Inter text globally
- Apply the orange glow `(drop-shadow 0 0 8px #ff7f11)` only on canvas component selection — not on Shiny UI cards
- Always attach units to RF numeric values in JetBrains Mono (`47.3 dBm`, `28 V`, `3.5 GHz`)
- Use `#ff7f11` for the single most important interactive element per view — scrollbar thumb, active selection, primary CTA
- Use `#00aaff` only for multi-selection and S-parameter/Smith chart overlays
- Apply `border: 2px solid #ff7f11` on the property editor — this is the one place where a solid accent border is correct
- Apply focus ring `0 0 0 2px rgba(255,127,17,0.20)` on every interactive Shiny element
- Use status colours (green / amber / red) only for design validation PASS/WARN/FAIL states
- Render all agent text blocks in JetBrains Mono on a `#0b0b0b` background

### Don't

- Don't use Electric Blue (`#3b82f6`) from the Global design system — this repo's primary accent is Signal Orange
- Don't add orange glow effects to Shiny UI components (buttons, cards, tabs) — glow is a canvas-only affordance
- Don't use weight 700 — this system caps at 600
- Don't use pure `#000000` or `#ffffff` as primary backgrounds — use the stepped neutrals
- Don't strip units from RF values in tables or output panels
- Don't skip the focus ring — `0 0 0 2px rgba(255,127,17,0.20)` on every interactive element
- Don't render agent output in Inter — JetBrains Mono is the agent voice
- Don't use Yellow (`#ffff00`) or Red (`#ff0000`) in Shiny UI — these are canvas-only RF glow error signals
- Don't apply confetti colours or decorative gradients — the instrument palette is deliberately monochromatic plus signal orange

---

## 8. Responsive Behavior

### Breakpoints

| Name | Width | Key Changes |
| --- | --- | --- |
| Mobile | < 640px | Not a primary target — RF design is a desktop/tablet task; warn user |
| Tablet (Lab Bench) | 768–1280px | Primary target for standing lab use; sidebar collapses to icon rail; canvas full width |
| Desktop | 1280–1920px | Full layout — fixed 250px sidebar + fluid main content |
| Wide | > 1920px | Centred max-width 1600px; canvas expands to fill |

### Touch Targets (Tablet / Lab Bench)

- Minimum tap target: 44×44px on tablet
- Canvas palette items: minimum 48px touch target
- Buttons: `min-height: 44px` on touch; `min-height: 36px` desktop
- Icon buttons: `padding: 10px` on touch devices

### Collapsing Strategy

- Sidebar: fixed 250px → icon-rail 56px (≥ 768px) → bottom nav or drawer (< 640px)
- PA lineup canvas: height fixed at 600px on desktop/tablet; horizontal scroll if viewport < 960px
- Plotly charts: responsive width; min-height 300px preserved on tablet
- Property editor: full-width slide-over on tablet (< 1024px)
- Tables: horizontal scroll below 768px; sticky first column when possible

---

## 9. Agent Prompt Guide

### Quick Color Reference

| Token | Value | When to Use |
| --- | --- | --- |
| Canvas background | `#0b0b0b` | PA lineup stage, outermost page shell |
| Panel background | `#1a1a1a` | Sidebar, cards, nav background |
| Property editor | `rgba(26,26,26,0.95)` | Floating panels, modals |
| Primary text | `#ffffff` | Headings, active labels |
| Secondary text | `#cccccc` | Body, descriptions, parameter labels |
| Muted text | `#888888` | Units, metadata, placeholders |
| Primary accent (orange) | `#ff7f11` | Primary CTA, selection state, scrollbar thumb |
| Secondary accent (blue) | `#00aaff` | Multi-select, Smith chart traces |
| Focus ring | `0 0 0 2px rgba(255,127,17,0.20)` | Keyboard focus, all interactive elements |
| Pass | `#22c55e` | Design validation PASS |
| Warning | `#f59e0b` | Approaching spec limit |
| Fail | `#ef4444` | Spec breach, agent error |

### Example Component Prompts

- **Property editor panel**: `"Background rgba(26,26,26,0.95). Border 2px solid #ff7f11. Radius 8px. Shadow 0 4px 20px rgba(0,0,0,0.5). Section heading: color #ff7f11, 16px Inter weight 600. Group labels: color #ccc, 12px weight 500 uppercase. Inputs: background #333, text #fff, border 1px solid #555, focus border #ff7f11."`

- **Spec compliance table (PASS/WARN/FAIL)**: `"Header: #1a1a1a background, 11px Inter weight 500 uppercase #888. Rows: alternating #0b0b0b / rgba(255,255,255,0.02). Row border 1px solid rgba(255,255,255,0.05). RF value cells: 13px JetBrains Mono #fff. PASS badge: rgba(34,197,94,0.15) bg, #22c55e text. WARNING badge: rgba(245,158,11,0.15) bg, #f59e0b text. FAIL badge: rgba(239,68,68,0.15) bg, #ef4444 text."`

- **Agent output panel**: `"Background #0b0b0b. Border 1px solid rgba(255,255,255,0.10). Radius 6px. Padding 12px 16px. Font JetBrains Mono 13px weight 400 #cccccc. Agent name label top-right: 11px Inter weight 500 uppercase #888, color #ff7f11."`

- **PA lineup canvas container**: `"Background #0b0b0b. Border-radius 8px. Height 600px. Selected component: drop-shadow(0 0 8px #ff7f11). Hovered component: drop-shadow(0 0 5px rgba(255,127,17,0.8)). Multi-selected: drop-shadow(0 0 10px #00aaff) opacity 0.95."`

- **Design flow tab (primary)**: `"Background #1a1a1a. Active tab: bottom border 2px #ff7f11, text #ffffff weight 600. Inactive tab: text #888 weight 500. Tab strip divider: 1px solid rgba(255,255,255,0.07)."`

- **Sidebar navigation**: `"Background #1a1a1a. Brand label: 16px Inter weight 600 #ff7f11. Nav items 14px weight 500, #ccc default, #fff hover, #ff7f11 active. Active item: 2px left border #ff7f11, rgba(255,127,17,0.08) background."`

- **Ropt / parameter chip**: `"Background rgba(255,127,17,0.15). Text: JetBrains Mono 12px weight 500 #ff7f11. Radius 4px. Padding 2px 8px. Example: [Ropt = 12.4 Ω]."`

### Iteration Guide

1. Set `font-feature-settings: "cv01", "ss03"` on all Inter text globally — non-negotiable.
2. Start every component on the correct surface: `#0b0b0b` → `#1a1a1a` → `rgba(26,26,26,0.95)`.
3. Borders are translucent white except the property editor, which takes `2px solid #ff7f11`.
4. Signal Orange (`#ff7f11`) goes on the one thing that matters most per view — not sprinkled broadly.
5. JetBrains Mono for any RF value, calculation result, or agent output; Inter for everything else.
6. Focus rings on every interactive element: `0 0 0 2px rgba(255,127,17,0.20)` — non-negotiable for accessibility.
7. Canvas glow states (hover/select/error) use `drop-shadow()` filters — never CSS `box-shadow` on Konva components.

---

## 10. UI Design Workflow & Quality Gate

### Core Principles

| Principle | Meaning in Practice |
| --- | --- |
| Cockpit principle | The most important action for the current design phase must be immediately visible — one glance, no hunting |
| Context-aware controls | Show the controls relevant to the current design tab; hide noise from other phases |
| Stable hierarchy | Users should immediately see what is primary (Ropt, PAE, Pout), secondary (matching elements), and supportive (metadata) |
| Zero-ambiguity units | Every RF value shown in the UI has a unit. No bare numbers. |
| Canvas as instrument | The PA lineup canvas is a measurement instrument, not a drawing tool. State changes communicate operational meaning. |
| Agent output is distinct | AI-generated text is always visually distinguishable from engineer-entered data (monospace, code-block container, agent label) |

### Design Procedure

1. Identify the user's primary task on the current design tab (e.g., selecting topology, entering power spec, reviewing Ropt).
2. Promote the primary input or result to full visual prominence; demote secondary controls.
3. Establish visual hierarchy before applying color details.
4. Apply tokens from this specification only — no arbitrary values.
5. Define hover, focus, active, and disabled states for every interactive element.
6. Verify layout at 1280px desktop and 768px tablet (lab bench use-case).
7. Confirm keyboard focus rings are present on all interactive controls.

### Quality Gate

- [ ] Primary action is first-glance discoverable (cockpit principle)
- [ ] All RF values have units in JetBrains Mono
- [ ] Agent output is in JetBrains Mono, code-block container, with agent name label
- [ ] Canvas component state uses glow, not box-shadow or border color changes
- [ ] No Yellow (`#ffff00`) or Red (`#ff0000`) outside the canvas component warning system
- [ ] Orange (`#ff7f11`) used once per view as the primary action signal
- [ ] Focus ring `0 0 0 2px rgba(255,127,17,0.20)` on every interactive Shiny element
- [ ] PASS/WARN/FAIL states use green/amber/red badges with muted backgrounds
- [ ] Responsive at 768px tablet and 1280px desktop
- [ ] No arbitrary hex values — all colours traceable to this specification

### Guardrails

- Do not port the Global design system's Electric Blue accent (`#3b82f6`) into this app
- Do not use orange glow effects on Shiny UI components — canvas only
- Do not display bare numeric RF values without units
- Do not render agent-generated recommendations in Inter — use JetBrains Mono
- Do not suppress the property editor border accent (`2px solid #ff7f11`) — it is how engineers know the panel is "live"
