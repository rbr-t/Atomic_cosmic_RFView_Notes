# CCPA / CPRA Reference — TKR Studios

> **Purpose**: Quick reference for the `compliance-checker` and `legal-guardian` agents.  
> Authority: California Consumer Privacy Act (Cal. Civ. Code §1798.100–1798.199.100)  
>             amended by California Privacy Rights Act (Proposition 24, effective 1 Jan 2023)  
> Regulator: California Privacy Protection Agency (CPPA)  
> **Not legal advice. Verify with qualified California privacy counsel.**

---

## 1. Does CCPA/CPRA Apply to TKR Studios?

A "covered business" must meet **at least one** threshold:

| Threshold | TKR Studios Status |
|---|---|
| Annual gross revenue > $25 million | [VERIFY — check actual revenue] |
| Annually buy/sell/share PI of ≥ 100,000 CA consumers or households | [VERIFY — check user volume] |
| Derive ≥ 50% annual revenue from selling/sharing PI | No — not a data broker business model |

**If none of the thresholds are met**: CCPA strict legal obligations may not apply, but including a California-style privacy policy clause demonstrates good faith and prepares the app for scale.

---

## 2. Key Defined Terms

| Term | Definition (CCPA §1798.140) |
|---|---|
| Personal Information (PI) | Information that identifies, relates to, describes, is capable of being associated with, or could reasonably be linked to a particular consumer or household |
| Sensitive Personal Information (SPI) | Specific categories including biometric data, precise geolocation, racial/ethnic origin, health data, sexual orientation, contents of email/texts unless sent to business |
| Sale | Disclosing PI to a third party for monetary or other valuable consideration |
| Sharing | Disclosing PI to a third party for cross-context behavioural advertising (regardless of monetary exchange) |
| Service Provider | Entity that processes PI on behalf of a business under a written contract that prohibits retention/use beyond providing services |
| Third Party | Neither the business nor a service provider |

---

## 3. TKR Studios PI Category Inventory

| CCPA Category | PI Collected | Source | Purpose | Disclosed To |
|---|---|---|---|---|
| Identifiers (A) | Email, Firebase UID, IP | User registration | Auth, service | Firebase (SP) |
| Internet Activity (F) | App usage logs | App analytics | Debugging | Railway (SP) |
| Photos/Visual (H) | User photographs | User upload | Album creation | AI providers (SP), Print partners (SP), Cloud (SP) |
| Biometric (E — SPI) | Facial images (if face recognition used) | User photos | Background removal, face tagging | Remove.bg (SP) |
| Geolocation (G — SPI if precise) | Not collected (shipping address = not precise geoloc.) | — | — | — |
| Inferences (K) | Layout/style preferences | App interaction | UI personalisation | Not disclosed |

**Sale/Sharing status**: None — TKR Studios does not sell or share PI.

---

## 4. Consumer Rights Summary (CPRA 2023)

| Right | Code Section | Deadline | Notes for TKR Studios |
|---|---|---|---|
| Right to Know | §1798.110–115 | 45 days (+45 days once) | Provide data export (JSON project files + account data) |
| Right to Delete | §1798.105 | 45 days | Account deletion flow; instruct service providers to delete |
| Right to Correct | §1798.106 | 45 days | Account settings; inform SPs of correction |
| Right to Opt-Out of Sale/Sharing | §1798.120 | Immediate | N/A — not selling/sharing. Add notice if practice changes |
| Right to Limit SPI Use | §1798.121 | 15 business days to comply | Opt-out mechanism needed if face recognition used at scale |
| Right to Non-Discrimination | §1798.125 | — | Do not deny service or charge different rates |
| Right to Appeal (Denial) | CPRA §1798.125(b)(4) | 45 days after denial | Must provide CPPA contact info in denial response |

---

## 5. Notice at Collection (§1798.100(b))

Must be provided at or before collection:
- [ ] Categories of PI collected
- [ ] Purpose(s) for which PI will be used
- [ ] Link to full Privacy Policy
- [ ] Link to "Do Not Sell or Share My Personal Information" (if applicable)
- [ ] If SPI collected: link to "Limit the Use of My Sensitive Personal Information"

**For TKR Studios**: Display at account registration and photo upload.

---

## 6. Privacy Policy Requirements (§1798.130(a)(5))

Annual update required. Must include:
- [ ] List of categories of PI collected in past 12 months
- [ ] Business purpose for each category
- [ ] Categories of third parties disclosed to (service providers vs. third parties)
- [ ] Consumer rights and how to exercise them
- [ ] Do Not Sell/Share notice (or statement that you do not)
- [ ] Retention periods for each category, or criteria used to determine them (CPRA addition)

---

## 7. Sensitive Personal Information (SPI) — Face Recognition Feature

If TKR Studios' optional face recognition / face tagging feature is enabled:

| Requirement | Status | Action |
|---|---|---|
| SPI disclosure in Privacy Policy | Required | Add to PI inventory |
| Purpose limitation | Required | Use only for stated purpose (face tagging within app) |
| Limit Use of SPI right | Required if "additional purposes" beyond service | Add opt-out mechanism |
| No inference-building from faces | Required | Confirm face data not used to infer characteristics |
| Service Provider contracts | Required | Update Remove.bg and any face recognition API contracts to prohibit broader use |

---

## 8. Verifiable Consumer Request (VCR) Process

Steps required:
1. Provide at least **two methods** to submit requests (e.g., email + webform)
2. Verify identity — match 2+ data points for access/delete; lower bar for opt-out
3. Respond within **45 calendar days** (first extension: additional 45 days with notice)
4. For access — provide in "portable and usable format" (JSON)
5. Free of charge (up to 2 requests/year; may charge for excessive/manifestly unfounded requests)
6. Keep records of requests and responses for **24 months** (CPRA record-keeping)
7. If using authorised agent — require written permission or PoA per §1798.135(c)

---

## 9. Service Provider & Contractor Contracts

Each third-party processor must have a written contract that:
- [ ] Prohibits retaining, using, or disclosing PI outside the service relationship
- [ ] Prohibits selling/sharing PI
- [ ] Requires the processor to delete PI upon request
- [ ] Grants the business audit rights
- [ ] Requires the processor to flow down obligations to sub-processors

Review contracts for: Firebase, Railway, all AI providers, print partners, Google Drive, Dropbox.

---

## 10. CPPA Contact

California Privacy Protection Agency  
2101 Arena Blvd, Sacramento, CA 95834  
[https://cppa.ca.gov](https://cppa.ca.gov)  

Enforcement actions under CPRA began July 1, 2023.

---

*Last reviewed: {{REVIEW_DATE}} — Verify against current CPPA regulations and Attorney General guidance.*
