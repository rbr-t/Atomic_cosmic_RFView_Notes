# UI Audit Checklist — TKR Studios

Run through this before marking any UI task done.

## 1. Collision / Overlap Check
- [ ] No absolute/fixed elements overlap body content without z-index intention
- [ ] All `position: absolute` elements have a `position: relative` parent explicitly set
- [ ] Tooltips / dropdowns have high enough z-index (`z-index: 9000+` for modals, `5000+` for dropdowns)
- [ ] No negative margins that pull elements into siblings
- [ ] Long text has `overflow: hidden` + `text-overflow: ellipsis` OR `overflow-wrap: break-word` — not raw overflow

## 2. Spacing
- [ ] All padding/margin uses `--sp-*` tokens
- [ ] No two clickable elements are closer than 8px (`--sp-8`) edge-to-edge
- [ ] Section headings have `margin-bottom: var(--sp-8)` before their content

## 3. Typography
- [ ] Font sizes use `--text-*` variables
- [ ] Body text is at least `--text-md` (never smaller than 13px)
- [ ] Headings follow the 5-level hierarchy (xl → lg → md → sm → xs)
- [ ] `font-weight: 600+` used only for headings and badges (not body)

## 4. Colour
- [ ] Text on `--surface` background passes WCAG AA (4.5:1 contrast minimum)
- [ ] Text on `--primary` background is `#fff` (check with contrast tool)
- [ ] Warning/error colours are not the sole indicator of state (also use icon)
- [ ] No more than 3 brand colours on a single screen

## 5. Interactivity
- [ ] Every button has: default / hover / active / focus-visible / disabled states
- [ ] Hover state changes background OR colour (not just cursor)
- [ ] focus-visible outline is `2px solid var(--primary)` minimum
- [ ] Disabled elements have `opacity: 0.45` and `pointer-events: none`
- [ ] Loading states: button text changes to spinner or "Saving…" during async ops

## 6. Touch / Mobile
- [ ] All tap targets ≥ 44×44px on screens ≤768px
- [ ] No hover-only interactions (touch devices have no hover)
- [ ] Drawers / panels have `overscroll-behavior: contain`
- [ ] Font sizes ≥ 16px on `<input>` elements (prevents iOS zoom)

## 7. Accessibility
- [ ] Icon-only buttons have `aria-label` or `title`
- [ ] Form inputs have associated `<label>` (not just placeholder)
- [ ] Color is not the only way to convey information
- [ ] `aria-live` region exists for dynamic status messages
- [ ] `@media (prefers-reduced-motion: reduce)` disables animations

## 8. Cockpit Principle
- [ ] Primary CTA visible without scrolling on 1024px viewport
- [ ] User can reach any main section in ≤ 1 click from anywhere
- [ ] Context panels show only controls relevant to current selection
- [ ] Empty states have a call-to-action (never a blank void)

## 9. i18n / l10n
- [ ] All visible strings use `t("key")` or have `data-i18n="key"` attribute
- [ ] Layout does not break when German/Finnish strings (30% longer than English) are used
- [ ] RTL languages: no hard-coded `text-align: left` or `padding-left` without RTL override
