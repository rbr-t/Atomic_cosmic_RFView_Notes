# AI Copyright Law Reference — TKR Studios

> **Purpose**: Quick reference for `copyright-scanner`, `compliance-checker`, and `legal-guardian` agents.  
> Covers: copyright ownership of AI-generated images, AI provider licence terms,  
>         user obligations, jurisdictional variation  
> **Not legal advice. Law in this area is rapidly evolving — verify with qualified IP counsel.**

---

## 1. Jurisdiction Summary: Can AI-Generated Images Be Copyrighted?

| Jurisdiction | Position | Authority | Notes |
|---|---|---|---|
| **United States** | No copyright without human authorship | *Thaler v. Vidal*, Fed. Cir. (2022); USPTO AI Copyright Guidance (Feb 2023); *Zarya of the Dawn* Copyright Office (2023) | Copyright requires "human authorship". AI-only outputs are not copyrightable. Human-directed elements (selection, arrangement, creative choices) may be. |
| **European Union** | No explicit AI authorship provision; requires human creative expression | Directive 2001/29/EC (InfoSoc); *Cofemel* C-683/17 (originality = author's own intellectual creation) | In practice: AI output without meaningful human creative choices likely unprotectable. EU AI Act doesn't create copyright. |
| **United Kingdom** | CDPA 1988 s.9(3): computer-generated works — copyright owned by the "person who makes the arrangements" | Copyright, Designs and Patents Act 1988 §9(3), §178 | UK uniquely recognises computer-generated works for 50 years. "Person who makes arrangements" = likely the human operating the AI tool (i.e., the user). Actively under review by UKIPO (2022 consultation). |
| **India** | No provision for AI authorship; copyright requires a human author | Indian Copyright Act 1957 s.2(d) — "author" = human | Computer-generated works not explicitly recognised. Outputs may be unprotectable. Under ongoing DPIIT/IPO review. |
| **Canada** | Copyright requires human authorship | Copyright Act (RSC 1985 c C-42) | Analogous to US position. No statutory provision for computer-generated works. |
| **Australia** | Copyright requires human authorship (IceTV, Telstra Corp cases) | Copyright Act 1968 (Cth) | No CDPA-style computer-generated works provision. |

---

## 2. AI Provider Licence Inventory

### 2.1 Stability AI (Stable Diffusion)

| Aspect | Detail |
|---|---|
| **Model licence** | Stable Diffusion models — CreativeML Open RAIL-M (older), or Stability AI Community Licence (newer models) |
| **Commercial use** | Generally permitted with use restrictions |
| **Restrictions** | Cannot use for: mass surveillance, disinformation targeting, fully automated decision making affecting legal rights, CSAM, violating others' rights |
| **Output ownership** | You own outputs subject to provider T&C and applicable law |
| **API T&C** | [https://stability.ai/terms-of-use](https://stability.ai/terms-of-use) — verify current version |
| **Training data claims** | Ongoing litigation (Getty Images v. Stability AI) — monitor |

### 2.2 OpenAI (DALL·E 3)

| Aspect | Detail |
|---|---|
| **Output ownership** | Users own outputs per OpenAI T&C (as of March 2023 update) |
| **Commercial use** | Permitted subject to Usage Policies |
| **Restrictions** | Cannot create CSAM, harassment content, disinformation, political content, impersonation, content violating others' rights |
| **Explicit copyright claims in DALL·E** | OpenAI states it trains DALL·E not to reproduce copyrighted styles verbatim — but outputs are NOT guaranteed copyright-free |
| **API T&C** | [https://openai.com/policies/usage-policies](https://openai.com/policies/usage-policies) |

### 2.3 Replicate

| Aspect | Detail |
|---|---|
| **Platform role** | Hosts third-party models. Each model has its own licence. |
| **Output ownership** | Depends on the specific model's licence |
| **Critical check** | Before using any Replicate model commercially: verify the model's own licence at the model page |
| **T&C** | [https://replicate.com/terms](https://replicate.com/terms) |

### 2.4 HuggingFace

| Aspect | Detail |
|---|---|
| **Platform role** | Model hub; each model has its own licence (MIT, Apache 2.0, CC-BY, RAIL-M, or proprietary) |
| **Output ownership** | Depends entirely on the specific model licence |
| **Critical check** | Read the licence card for each model used |
| **Common model licences** | `stabilityai/stable-diffusion-xl-base-1.0` → Community Licence; `runwayml/stable-diffusion-v1-5` → CreativeML RAIL-M |

### 2.5 DeepAI

| Aspect | Detail |
|---|---|
| **Output ownership** | Users own outputs per DeepAI terms |
| **Commercial use** | Permitted with paid plan |
| **T&C** | [https://deepai.org/terms-of-service](https://deepai.org/terms-of-service) |

### 2.6 Remove.bg (Kaleido AI)

| Aspect | Detail |
|---|---|
| **Data use** | Processes photos to remove backgrounds; check data retention and AI training clauses |
| **T&C** | [https://www.remove.bg/terms](https://www.remove.bg/terms) |
| **Privacy** | [https://www.remove.bg/privacy](https://www.remove.bg/privacy) |

---

## 3. Key Legal Cases & Guidance

| Case / Guidance | Jurisdiction | Key Holding |
|---|---|---|
| *Thaler v. Vidal*, 43 F.4th 1207 (Fed. Cir. 2022) | USA | AI cannot be named as inventor under patent law — requires human |
| *Zarya of the Dawn* — Copyright Office Ruling (Feb 2023) | USA | Comic using AI Midjourney images: images alone not copyrightable; human-authored text + selection arrangement copyrightable |
| *Getty Images Inc. v. Stability AI Ltd* (2023) | UK & USA | Pending: alleges training on Getty images = infringement. Monitor for outcome. |
| *Andersen v. Stability AI, Midjourney, DeviantArt* (2023) | USA | Pending: alleges training on artists' works = infringement |
| USPTO AI & Copyright Guidance (Feb 2023) | USA | AI-generated content must have "human authorship" for protection; disclose AI use when known |
| US Copyright Office Notice of Inquiry (2023) | USA | Soliciting input on AI copyright policy — final guidance pending |
| EU AI Act (Regulation 2024/1689) | EU | Art. 50: transparency requirements for AI-generated content ("AI-generated" labelling); no copyright creation |
| UKIPO AI Copyright Consultation (2022) | UK | Proposed options including miner's exception for AI training; current CDPA s.9(3) maintained pending further consultation |

---

## 4. Risk Matrix for TKR Studios Features

| Feature | Copyright Risk | Risk Level | Mitigation |
|---|---|---|---|
| AI image generation for personal album use | Output ownership depends on provider T&C; low risk for personal use | Low | Provide users disclosure that outputs may not be copyrighted |
| AI image generation for commercial printing | Higher risk — copyright status unclear in most jurisdictions | Medium | Warn users commercial use may require legal advice; check provider commercial terms |
| Using Replicate/HuggingFace models without checking licence | Model licence may prohibit commercial use | High | Check each model's licence before enabling in app |
| AI training on user-uploaded photos | Without explicit consent: potential GDPR, CCPA, DPDP violation + IP issue | Critical | Do NOT train on user data without explicit separate consent and DPA update |
| Getty / stock images as AI inputs | Could constitute style replication dispute | Medium | Consider filtering or warning when identifiable stock images are described in prompts |
| Displaying AI-generated images without "AI-generated" label | EU AI Act Art. 50 compliance required from Aug 2026 | Medium (growing) | Add AI-generated metadata/watermark to outputs |

---

## 5. Recommended App Disclosures

Add to UI near AI generation feature:

> **Copyright Notice**: Images generated using AI tools may not be protected by copyright in your jurisdiction. Verify copyright status and commercial use rights before using AI-generated images in commercial print products. Each AI provider's terms apply.

Add to Terms & Conditions (see `clauses/ai-generated-content.html`).

---

## 6. AI Act Transparency (EU) — Implementation Checklist

From 2 August 2026 (or earlier for GPAI models):
- [ ] Label AI-generated images within the app UI (e.g., "AI-generated" badge / metadata)
- [ ] Enable user to download AI-generated images with embedded metadata indicating AI origin
- [ ] Do not suppress C2PA or similar provenance signals
- [ ] Provide clear disclosure in T&C about AI use

---

## 7. Ongoing Monitoring

These areas are actively evolving — quarterly review recommended:

- [ ] US Copyright Office AI Copyright Final Report (expected 2024–2025)
- [ ] Getty v. Stability AI outcome (UK + USA)
- [ ] EU implementing acts under AI Act (Art. 50 technical standards)
- [ ] UK CDPA s.9(3) reform following UKIPO consultation
- [ ] India Copyright Act review (DPIIT)
- [ ] Australia AGIMO / AIIG guidance on AI-generated works

---

*Last reviewed: {{REVIEW_DATE}} — This is one of the fastest-evolving areas of law. Verify all positions before relying on them.*
