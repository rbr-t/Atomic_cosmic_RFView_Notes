# India DPDP Act Reference — TKR Studios

> **Purpose**: Quick reference for the `compliance-checker` and `legal-guardian` agents.  
> Authority: Digital Personal Data Protection Act 2023 (Act No. 22 of 2023)  
>             Received Presidential assent: 11 August 2023  
>             Rules: Draft DPDP Rules published 3 January 2025 (finalization pending as of early 2025)  
> Regulator: Data Protection Board of India (DPB) — not yet formally constituted as of early 2025  
> **Not legal advice. Verify with qualified Indian data protection counsel.**

---

## 1. Applicability to TKR Studios

The DPDP Act applies to:
- Processing of **digital personal data** within India
- Processing outside India if offering goods/services to persons within India

**TKR Studios**: If Indian users can access and register for the Service → **Act applies**.

---

## 2. Key Defined Terms (DPDP Act 2023)

| Term | Definition |
|---|---|
| Personal Data | Any data about an individual who is identifiable by / in relation to such data |
| Digital Personal Data | Personal data in digital form |
| Data Fiduciary | Person who, alone or with others, determines the purpose and means of processing |
| Data Processor | Person who processes personal data on behalf of a Data Fiduciary |
| Data Principal | Individual to whom the personal data relates (i.e., the user) |
| Significant Data Fiduciary (SDF) | Notified by Central Government based on volume/sensitivity of data processed |
| Consent Manager | Entity registered with DPB to manage consent on behalf of Data Principals |

---

## 3. Lawful Bases for Processing (s.4–7)

### 3.1 Consent (s.5–6)
- Consent must be **free, specific, informed, unconditional, and unambiguous**
- Must be accompanied by a **notice** (s.5) provided before or at the time of consent in a clear and plain language
- Notice must describe: what data is collected, purpose of processing
- A single notice can cover multiple processing activities
- Consent can be withdrawn at any time (s.6(4)) — withdrawal must be as easy as giving consent

### 3.2 Legitimate Uses (s.7 — deemed consent)
These do not require explicit consent:
- Specified purposes voluntarily provided by Data Principal
- **State and its instrumentalities** — for subsidies, benefits, services, licences, permits
- **Legal obligation compliance**
- Medical emergency threatening life / epidemic
- Employment-related processing under law
- **Reasonable purposes** notified by Central Government (list to be prescribed in Rules)

**For TKR Studios**: Account creation, album processing, and print fulfilment are likely covered under s.7(a) (Data Principal voluntarily provides data for stated purpose). Verify with counsel.

---

## 4. Obligations of Data Fiduciary (s.8–10)

### 4.1 Core Obligations (s.8)

| Obligation | Detail |
|---|---|
| Purpose limitation | Process data only for the specified purpose |
| Data quality | Take reasonable steps to ensure data is accurate/complete for the purpose |
| Storage limitation | Retain data only as long as necessary for the purpose; **erase data when purpose is served** unless retention required by law |
| Security safeguards | Implement reasonable security measures to prevent breach |
| Breach notification | Notify DPB (and affected Data Principals per Rules) of breach in a manner and within timeline to be prescribed |
| Grievance redressal | Establish mechanism to address Data Principal grievances; designate a **Grievance Officer** |

### 4.2 Children's Data — Significant Restriction (s.9)

- Must obtain **verifiable parental consent** before processing personal data of a child (under 18)
- Must not process personal data in ways that are **detrimental to the wellbeing** of a child
- Must not undertake **tracking or behavioural monitoring** of children
- Must not **target advertising** to children

**For TKR Studios**: Add age-gate (18+ confirmation at sign-up) or parental consent flow. This is a hard requirement — no exemption for "inadvertent" collection.

### 4.3 Additional SDF Obligations (if notified) (s.10)
- Data Protection Officer (DPO) resident in India
- Independent audit of data protection measures
- Data Protection Impact Assessment (DPIA) for high-risk processing
- Restrictions on cross-border data transfers (Rules to specify)

---

## 5. Rights of Data Principal (s.11–14)

| Right | DPDP Section | Notes |
|---|---|---|
| Right to access information | s.11 | Must provide: confirmation of processing, categories processed, others to whom data shared |
| Right to correction and erasure | s.12 | On request, correct inaccurate data; complete incomplete data; erase data no longer necessary (unless law requires retention) |
| Right of grievance redressal | s.13 | Must acknowledge and resolve grievance within prescribed timeline (Rules to specify) |
| Right to nominate | s.14 | Nominate another person to exercise rights in case of death/incapacity |

---

## 6. Data Principal Duties (s.15)

Data Principals also have duties (this is a distinctive feature of the DPDP Act):
- Must not register false or suppressed information
- Must not impersonate another individual
- Must not suppress material information required to be disclosed
- Must comply with applicable laws

---

## 7. Significant Data Fiduciary Criteria (s.10)

Central Government may notify an entity as SDF based on:
- Volume and sensitivity of personal data processed
- Risk to rights of Data Principals
- National security or public order implications
- Risk to electoral democracy
- Sovereignty or integrity of India

**Assessment for TKR Studios (early stage)**: Unlikely to be notified as SDF. Monitor if user base grows to millions.

---

## 8. Cross-Border Data Transfers (s.16)

- Personal data of Indian users may be transferred to other countries **except** countries notified (blacklisted) by Central Government
- Positive "whitelist" model possible (Government may notify allowed countries)
- Rules not yet finalized — monitor [meity.gov.in](https://www.meity.gov.in) for notifications
- **Draft Rules 2025** propose significant restrictions — verify current status

---

## 9. Grievance Officer Requirement

The DPDP Act requires a named **Grievance Officer** for Data Principals in India to contact:
- Must be an individual (not just an inbox)
- Name and contact must be published in Privacy Policy
- Must acknowledge/respond to grievances within prescribed timeline (Rules pending)

**Action**: Designate a Grievance Officer (can be the founder / developer until Rules specify otherwise). Add to Privacy Policy contact section.

---

## 10. Penalties (s.33)

| Violation | Maximum Penalty |
|---|---|
| Personal data breach (failure to implement security safeguards) | ₹ 250 crore (~USD 30M) |
| Failure to notify breach to DPB | ₹ 200 crore (~USD 24M) |
| Breach of child data obligations | ₹ 200 crore (~USD 24M) |
| Significant Data Fiduciary violations | ₹ 150 crore (~USD 18M) |
| Other violations | ₹ 50 crore (~USD 6M) |

Penalties are imposed by the Data Protection Board after inquiry.  
**Note**: Rules and Board not yet fully constituted — monitor enforcement timeline.

---

## 11. Compliance Checklist for TKR Studios

- [ ] Privacy Policy updated with: data categories, purposes, Grievance Officer details
- [ ] Grievance Officer named (name + email in Privacy Policy)
- [ ] Age-gate at registration: 18+ verification (verifiable parental consent if under-18 allowed)
- [ ] Children's tracking / behavioural advertising features: NOT implemented
- [ ] Consent notice displayed before data collection at registration
- [ ] Consent withdrawal mechanism available (no harder than giving consent)
- [ ] Data retention schedule: erase user data when account deleted (not needed for other legal purposes)
- [ ] Security safeguards: encryption at rest (cloud tokens), in transit (HTTPS) — already implemented
- [ ] Breach notification plan: identify DPB once established; draft notification template
- [ ] Cross-border transfer: monitor MEITY whitelist notifications for Railway/Firebase/AI provider countries

---

*Last reviewed: {{REVIEW_DATE}} — Rules currently in draft (January 2025). Verify finalized Rules before implementation.*  
*Reference: [meity.gov.in/data-protection](https://www.meity.gov.in/data-protection)*
