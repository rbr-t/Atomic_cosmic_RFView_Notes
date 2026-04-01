---
name: legal-document
description: "Generate rich, accessible, print-ready legal HTML documents for TKR Studios: Terms & Conditions, Privacy Policy, EULA, Cookie Notice, AI Content Disclaimer, Acceptable Use Policy, Data Processing Agreement. Use when: drafting or updating any user-facing legal page, producing a compliance document, generating a Terms of Service for app store publishing, or preparing a Data Processing Agreement. Produces WCAG 2.1 AA accessible HTML with TOC, day/night toggle, printable PDF-ready layout, and jurisdiction badges."
argument-hint: "Which document to generate: terms, privacy, eula, cookie, ai-disclaimer, aup, dpa — and any specific jurisdictions to emphasise"
---

# Legal Document Skill — TKR Studios

Produces polished, accessible, jurisdiction-aware HTML legal documents from templates.
All output saved to `www/legal/drafts/` as draft for human/solicitor review before publication.

## Feature Checklist

| Feature | Implementation |
|---------|---------------|
| TOC | Floating sidebar with anchor links to each clause |
| Day / Night toggle | CSS variables with JS toggle (same as rich-document skill) |
| Jurisdiction badges | Inline `<span class="badge-jurisdiction">` per clause |
| Print layout | `@media print` — hides nav, toggle; black-on-white |
| Accessibility | WCAG 2.1 AA — semantic HTML, ARIA, 4.5:1 contrast |
| Version tracking | `<!-- Version: X.Y — Date: YYYY-MM-DD — DRAFT -->` |
| Plain language | Short sentences, no Latin legalese, grade 10 reading level target |

---

## Step-by-Step Procedure

### Step 1 — Identify document and jurisdiction

Determine from context:
- Which document is needed (terms / privacy / eula / cookie / ai-disclaimer / aup / dpa)
- Which jurisdictions apply (default: India + EU + USA)
- Whether updating an existing draft or creating fresh

### Step 2 — Load the correct template

Copy the relevant template from [assets/](./assets/) as the starting skeleton:

| Document | Template file |
|----------|--------------|
| Terms & Conditions | [assets/terms-template.html](./assets/terms-template.html) |
| Privacy Policy | [assets/privacy-template.html](./assets/privacy-template.html) |
| EULA | [assets/eula-template.html](./assets/eula-template.html) |
| Cookie Notice | [assets/cookie-template.html](./assets/cookie-template.html) |
| AI Content Disclaimer | [assets/ai-disclaimer-template.html](./assets/ai-disclaimer-template.html) |

### Step 3 — Populate app-specific placeholders

Replace all `{{PLACEHOLDER}}` tokens:

| Token | Value |
|-------|-------|
| `{{APP_NAME}}` | TKR Studios |
| `{{COMPANY_NAME}}` | TKR Studios |
| `{{CONTACT_EMAIL}}` | *(insert support email)* |
| `{{EFFECTIVE_DATE}}` | Current date |
| `{{JURISDICTION}}` | Primary jurisdiction |
| `{{GOVERNING_LAW}}` | *(insert country/state)* |
| `{{DISPUTE_FORUM}}` | *(insert court/arbitration)* |
| `{{GRIEVANCE_OFFICER}}` | *(insert name — required by India DPDP)* |
| `{{DATA_RETENTION_MONTHS}}` | 24 (default — confirm with engineering) |
| `{{MIN_AGE}}` | 13 (confirm COPPA assessment) |

### Step 4 — Apply jurisdiction overlays

For each clause, add applicable jurisdiction badges using:
```html
<span class="badge-jurisdiction gdpr">GDPR</span>
<span class="badge-jurisdiction dpdp">DPDP</span>
<span class="badge-jurisdiction ccpa">CCPA</span>
```

Clause presence requirements:

| Clause | GDPR | DPDP | CCPA | Always |
|--------|------|------|------|--------|
| Lawful basis for processing | ✅ | ✅ | — | — |
| Data subject rights | ✅ | ✅ | ✅ | — |
| Do Not Sell link | — | — | ✅ | — |
| Grievance Officer contact | — | ✅ | — | — |
| Cookie consent | ✅ | — | — | — |
| AI image labelling notice | EU AI Act | — | — | ✅ |
| Children's data | COPPA | ✅ | COPPA | ✅ |
| Breach notification | 72hr | — | — | ✅ |

### Step 5 — Add mandatory app-specific sections

Every document must include these TKR Studios sections (text in [assets/clauses/](./assets/clauses/)):

- `ai-generated-content.html` — AI image ownership + EU AI Act Art. 50 notice
- `user-photos-ownership.html` — User retains all rights to uploaded photos
- `print-fulfilment.html` — Printful/Gelato/Printify liability limitation
- `cloud-storage-oauth.html` — Google Drive / Dropbox token scope disclosure
- `firebase-auth.html` — Firebase data processing disclosure

### Step 6 — Save and annotate

Save to `www/legal/drafts/<document-name>.html` with:
```html
<!-- 
  DRAFT — NOT FOR PUBLICATION
  Generated: {{DATE}}
  Version: 1.0-draft
  Requires review by qualified legal counsel before publication.
  TKR Studios Legal Guardian Agent
-->
```

### Step 7 — Return review summary

State:
1. File path saved
2. Placeholders still requiring human input (`{{...}}` tokens remaining)
3. Top 3 clauses requiring solicitor review before publishing

---

## CSS Classes Reference

```css
.badge-jurisdiction       /* base badge style */
.badge-jurisdiction.gdpr  /* blue — EU */
.badge-jurisdiction.dpdp  /* green — India */
.badge-jurisdiction.ccpa  /* orange — California */
.badge-jurisdiction.uk    /* purple — UK */
.badge-jurisdiction.coppa /* red — children */
```

Defined in [assets/legal.css](./assets/legal.css).

---

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Blank `{{GOVERNING_LAW}}` in ToS | Must be filled — blank jurisdiction clause is unenforceable |
| AI ownership clause missing | Every ToS for this app needs it — Replicate + HuggingFace models have RAIL restrictions |
| Cookie notice too vague | GDPR requires purpose + duration per cookie category |
| Grievance Officer missing | India DPDP s.13 — mandatory named contact with response SLA |
| Version number not incremented | Always bump minor version on any clause change |
| Draft served at production URL | Only publish from `www/legal/` not `www/legal/drafts/` |
