---
description: "Engineering quality standards for all TKR Studios specialist agents. Enforces: anomaly-first scanning before any implementation, evidence-cited findings with file:line references, POV checks before final output, and feedback-ready structured output. Apply to all specialist agent work sessions."
applyTo: ".github/agents/**"
---

# Specialist Agent Quality Standards

All TKR Studios specialist agents MUST follow these standards on every task. These are enforced by the **Deep Specialist** feedback layer and reviewed by **Mission Compass**.

---

## 1. Anomaly-First Scan (mandatory — before any edit)

Before writing a single line of code or making any edit, scan the target area for anomalies and fundamental flaws. Output the result as the **first thing** in your response:

```
⚠ ANOMALY CHECK — [file or area being modified]
  CRITICAL: [issue] at [file:line] — [consequence]
  HIGH:     [issue] at [file:line] — [consequence]
  NONE FOUND — proceeding.
```

Do not proceed past a CRITICAL finding without explicit user acknowledgement.

---

## 2. Evidence-Cited Findings

Every claim, finding, or recommendation must include a reference:

- **Code claim** → `file.R:line_number` (exact)
- **External claim** → URL or standard name (e.g., OWASP A03, RFC 7519)
- **Assumption** → Explicitly labelled `[ASSUMPTION]` — not presented as fact

Never paraphrase error messages, approximate line numbers, or assert behaviour without reading the actual code.

---

## 3. POV Check Before Final Output

Before delivering your final output on any non-trivial task, run a brief internal POV check across three layers:

- **Layer above (Mission Compass):** Does this output serve the original goal? Does it introduce drift?
- **Self:** Am I within my domain? Is my confidence calibrated? Did I miss anything obvious?
- **Layer below (implementing process / user):** Is my output actionable? Does it create hidden rework?

If a POV check reveals a conflict or gap, surface it — do not suppress it to appear complete.

---

## 4. Feedback-Ready Output Structure

Structure every significant output so the Deep Specialist can review it efficiently:

- State **what was changed and why** at the top (not buried at the end)
- Reference **each modified file:line** explicitly
- List any **side effects or dependencies** that were touched
- Declare your **confidence level**: HIGH / MEDIUM / LOW + one-line reason

---

## 5. Realism and Result Orientation

- Connect every finding to a **consequence** — "this is wrong" is incomplete without "and therefore X will fail"
- When multiple approaches exist, state the **trade-off explicitly** — never silently choose the convenient one
- Do not recommend solutions that are theoretically correct but practically impossible given codebase constraints — flag the gap instead
- Prefer **minimal, reversible changes** over comprehensive rewrites unless a rewrite is genuinely necessary and justified
