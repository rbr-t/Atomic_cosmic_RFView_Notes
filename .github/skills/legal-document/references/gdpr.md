# GDPR Reference — TKR Studios

> **Purpose**: Quick reference for the `compliance-checker` and `legal-guardian` agents.  
> Authority: Regulation (EU) 2016/679 — General Data Protection Regulation  
> Applicability: EU/EEA data subjects; UK GDPR (post-Brexit) mirrors same structure  
> **Not legal advice. Verify with qualified EU data protection counsel.**

---

## 1. Key Articles Mapped to App Features

| App Feature | GDPR Article(s) | Requirement |
|---|---|---|
| User account creation (email/FirebaseUID) | Art. 6(1)(b) — Contract | Lawful basis: contract performance |
| Google Sign-In OAuth | Art. 6(1)(a) — Consent | Document consent scope and withdrawal path |
| User photo upload | Art. 9(2)(a) if biometric / Art. 6(1)(b) | Photos with faces = potential biometric data (Art. 4(14)) only if processed for unique ID |
| Cloud storage (Google Drive/Dropbox) | Art. 6(1)(b); Art. 28 — Processor | DPA required with Google/Dropbox as processors |
| AI image generation (Stability AI, OpenAI, etc.) | Art. 6(1)(b); Art. 28 | DPAs with each AI provider; evaluate Art. 22 if any automated profiling |
| Remove.bg background removal | Art. 9 — biometric, Art. 28 | If faces present; DPA required with Remove.bg |
| Print fulfilment (Printful, Gelato, Printify) | Art. 28 — Processor | DPA required; data minimisation — send only what's needed |
| Security / access logs | Art. 6(1)(f) — Legitimate interests | LIA required; minimise retention |
| Analytics / usage data | Art. 6(1)(a) or (f) | If identifiable, may need consent; consider pseudonymisation |
| App hosted on Railway.app | Art. 44 — Cross-border transfer | Railway = US; requires SCCs or DPF adequacy |

---

## 2. Core Principles Checklist (Art. 5)

- [ ] **Lawfulness, fairness, transparency** — privacy notice published, lawful basis documented
- [ ] **Purpose limitation** — data used only for specified purposes; no repurposing without new basis
- [ ] **Data minimisation** — only collect what is necessary
- [ ] **Accuracy** — provide access/rectification mechanism
- [ ] **Storage limitation** — retention schedule documented and enforced
- [ ] **Integrity & confidentiality** — encryption at rest and in transit; access control
- [ ] **Accountability** — records of processing activities (ROPA) maintained (Art. 30)

---

## 3. Data Subject Rights Summary

| Right | Article | Response Time | Applies to App |
|---|---|---|---|
| Right to access | Art. 15 | 1 month (extendable 2×) | Yes |
| Right to rectification | Art. 16 | 1 month | Yes (account settings) |
| Right to erasure | Art. 17 | 1 month | Yes (account deletion) |
| Right to restriction | Art. 18 | Without undue delay | Yes |
| Right to portability | Art. 20 | 1 month | Yes (JSON export of projects) |
| Right to object | Art. 21 | Upon receipt | Yes (legitimate interests processing) |
| Rights re: automated decisions | Art. 22 | Without undue delay | Likely N/A (no automated profiling) |
| Right to withdraw consent | Art. 7(3) | At any time | Yes (AI features using consent basis) |

---

## 4. Article 28 — Processor Agreements Required

For each third-party that processes personal data on behalf of the controller:

| Processor | Data Processed | DPA Status |
|---|---|---|
| Google Firebase | Account data, auth tokens | Google T&C includes DPA (verify current version) |
| Railway.app | All app data (hosting) | [CHECK — review Railway DPA/BAA availability] |
| Stability AI | Prompt text, AI outputs | [CHECK — review Stability AI DPA terms] |
| OpenAI | Prompt text, AI outputs | OpenAI has Data Processing Addendum (verify) |
| Replicate | Prompt text, AI outputs | [CHECK — review Replicate DPA terms] |
| HuggingFace | Prompt text, AI outputs | [CHECK — review HuggingFace DPA terms] |
| DeepAI | Prompt text, AI outputs | [CHECK — review DeepAI DPA terms] |
| Remove.bg (Kaleido.ai) | Photos (may contain faces) | [CHECK — review Remove.bg DPA terms] |
| Printful | Photos, shipping address | Printful has data processing terms (verify) |
| Gelato | Photos, shipping address | [CHECK — review Gelato DPA] |
| Printify | Photos, shipping address | [CHECK — review Printify DPA] |
| Google Drive | Album project files | Google Workspace DPA (verify user vs workspace context) |
| Dropbox | Album project files | Dropbox DPA for Business (verify applicability) |

---

## 5. Article 44 — Cross-Border Transfer Mechanisms

App hosted on Railway (US). AI providers mostly US-based.

| Mechanism | Status | Notes |
|---|---|---|
| EU-US Data Privacy Framework (DPF) | Active (as of July 2023) | Replaces Privacy Shield. Verify if processor is DPF-certified at [dataprivacyframework.gov](https://www.dataprivacyframework.gov/) |
| Standard Contractual Clauses (SCCs) | Active | EC Decision 2021/914. Use Module 2 (Controller-to-Processor) |
| UK International Data Transfer Agreement (IDTA) | For UK transfers | Use IDTA or UK Addendum to SCCs |
| Adequacy decision | N/A for US | No EU adequacy decision for US; use DPF or SCCs |

---

## 6. DPO Requirement (Art. 37)

DPO is **mandatory** where:
- Core activities require large-scale, regular and systematic monitoring, **or**
- Core activities involve large-scale processing of special category data

**Assessment for TKR Studios**: Photos with faces = potential biometric data only if processed for unique identification. If face recognition feature is enabled for significant user base → DPO likely required. If feature is opt-in and minimal → assess case-by-case. **Recommend LIA + DPA counsel assessment.**

---

## 7. Records of Processing Activities (Art. 30)

Must maintain ROPA documenting:
- Name/contact of controller
- Purpose of processing
- Categories of data subjects and data
- Categories of recipients
- Cross-border transfers and safeguards
- Intended retention periods
- Security measures

---

## 8. Privacy by Design (Art. 25)

Key requirements for ongoing development:
- Data minimisation at design stage
- Pseudonymisation where possible
- Default settings = most privacy-protective
- No more data collected than necessary
- New features require privacy impact review

---

## 9. DPIA Triggers (Art. 35)

A Data Protection Impact Assessment (DPIA) is required before processing that is "likely to result in high risk":
- Large-scale processing of biometric data (face recognition feature)
- New AI processing of user photos at scale
- Automated content moderation deciding account access

**Likely required if**: face recognition feature expanded, AI training on user photos, or usage analytics becomes large-scale profiling.

---

## 10. Supervisory Authorities (Key)

| Country | Authority | Website |
|---|---|---|
| EU (lead) | Depends on controller's EU establishment | EDPB member list |
| Germany | BfDI (federal) + Länder authorities | bfdi.bund.de |
| France | CNIL | cnil.fr |
| Netherlands | AP | autoriteitpersoonsgegevens.nl |
| Ireland | DPC (Google, Meta lead SA) | dataprotection.ie |
| UK | ICO | ico.org.uk |

---

*Last reviewed: {{REVIEW_DATE}} — Verify against current EDPBoard guidelines and national DPA guidance.*
