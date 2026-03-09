# PA Lineup — Calculation Flow & Architecture

> **Document purpose:** Explains the end-to-end calculation approach for the PA Lineup tool — from user input, through the R engine, through the JS canvas display, to the results panels.

---

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  USER INPUTS (Shiny UI)                                                     │
│                                                                             │
│  ┌──────────────────────┐    ┌──────────────────────┐                      │
│  │  Lineup Specifications│    │  Global Lineup Params │                     │
│  │  ─────────────────── │    │  ─────────────────── │                     │
│  │  • Center Freq (MHz)  │    │  • Freq (GHz)         │                    │
│  │  • Pout = P(X)dB (dBm)│◄──►│  • Pout = P(X)dB (dBm)│  (synced)        │
│  │  • PAR / BO (dB)     │    │  • Back-off (dB)      │                    │
│  │  • Total Gain (dB)    │    │  • PAR (dB)           │                    │
│  │  • System PAE (%)     │    │  • Pout = P(X)dB sel. │                    │
│  │  • Compression: P(X)dB│    │  ─────────────────── │                    │
│  └──────────┬───────────┘    └──────────┬────────────┘                     │
│             │  syncLineupSpecs                │                             │
│             ▼                               ▼                              │
│  ┌──────────────────────────────────────────────────┐                      │
│  │           Canvas (D3.js / pa_lineup_canvas.js)   │                      │
│  │  • Components: transistor, matching, splitter,   │                      │
│  │    combiner, doherty_combiner                    │                      │
│  │  • Component properties: gain, PAE, Vdd, P1dB,  │                      │
│  │    pout, rth, z_in, z_out, …                     │                      │
│  │  • Connections (signal graph)                    │                      │
│  │  ─────────────────────────────────────────────── │                      │
│  │  JS Preview calculations (before R sync):        │                      │
│  │    calculateComponentPower() per component       │                      │
│  │    → drawPowerColumns(), drawGainColumns(),       │                      │
│  │      drawPAEColumns(), drawImpedanceColumns()    │                      │
│  └──────────────────────┬───────────────────────────┘                      │
│                         │  input$lineup_components (JSON)                  │
│                         │  input$lineup_connections (JSON)                 │
└─────────────────────────┼───────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  R ENGINE  (server_pa_lineup.R → calc_pa_lineup.R)                         │
│                                                                             │
│  Trigger: "Calculate" button (input$lineup_calculate)                      │
│  ─────────────────────────────────────────────────────────────────────────  │
│  1. Read components + connections from reactive values                      │
│  2. Determine input_power = spec_p3db − spec_gain  (Pin to first stage)    │
│  3. backoff_value = spec_par (PAR)                                          │
│  4. Call: lineup_calculate_engine(components, connections,                  │
│              input_power, backoff_value)                                    │
│     → calc_pa_lineup.R:                                                     │
│        a. Topology sort (connection graph → ordered stage list)             │
│        b. Per-stage loop:                                                   │
│           • transistor: pout = pin + gain, PAE, PDC, Pdiss, Tj              │
│           • matching:   pout = pin − loss                                  │
│           • splitter:   pout = pin − 10·log10(ways) − loss                 │
│           • combiner:   pout = sumdbm(all inputs) − loss                   │
│        c. Collect stage_results[] with per-stage pin, pout, gain, PAE,     │
│           PDC, Pdiss, compressed flag                                       │
│        d. Aggregate: final_pout, total_gain, system_PAE,                   │
│           total_PDC, total_Pdiss                                            │
│        e. Repeat at backoff (Pavg operating point)                          │
│        f. Generate rationale text                                           │
│  5. Store result → lineup_calc_results() reactive                          │
│  6. Sync per-stage results back to canvas:                                  │
│     session$sendCustomMessage("updateComponentProperties", …)              │
│     → props updated: pout_p3db, pout_pavg, pin_p3db, pin_pavg, pae_p3db   │
└─────────────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  RESULTS DISPLAY                                                            │
│                                                                             │
│  ┌─────────────────────────┐  ┌──────────────────────────────────────────┐ │
│  │ Calculation Results box │  │ Equations & Rationale tabbox             │ │
│  │ (right sidebar)         │  │ ────────────────────────────────────────  │ │
│  │  • Full Power perf.     │  │  Tab: Power  — power cascade formulas +  │ │
│  │  • Backoff perf.        │  │    per-stage Pin/Pout/Stage-G table      │ │
│  │  • Total Gain           │  │  Tab: Gain   — gain formulas + per-stage │ │
│  │  • Warnings             │  │    gain table                            │ │
│  └─────────────────────────┘  │  Tab: PAE    — efficiency formulas +     │ │
│                               │    per-stage PAE/PDC/Pdiss table         │ │
│                               └──────────────────────────────────────────┘ │
│                                                                             │
│  Canvas overlays (real-time, re-drawn after R sync):                       │
│    • Power boxes  (Pin / Pout / P1dB / P_BO)                               │
│    • Gain bars    (stage gain height-coded)                                 │
│    • PAE bars     (PAE % height-coded)                                      │
│    • Impedance    (Z_in / Z_out / Z_opt)                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Detailed Calculation Flow

### 2.1 Specification → Cascade Entry Point

```
spec_frequency (MHz)    →  divide by 1000  →  freq_ghz (for JS + calculations)
spec_p3db      (dBm)    →  Pout operating point  (the PXdB chosen by user)
spec_par       (dB)     →  PAR = peak-to-average ratio = system back-off
spec_gain      (dB)     →  used to back-calc Pin = spec_p3db − spec_gain
spec_compression_point  →  label only (P1dB / P2dB / P3dB / P5dB)
                           ALL cascade math uses spec_p3db as "Pout"

Derived:
  Pavg (dBm)  = spec_p3db − spec_par       ← average operating power
  Pin  (dBm)  = spec_p3db − spec_gain      ← first-stage input
```

### 2.2 Stage-by-Stage Power Cascade (R engine)

```
For each stage i (topologically ordered):

  ── Transistor ──────────────────────────────────────────────────────
  If JS has pre-synced pout_p3db:
    pout_dbm = pout_p3db  (R trusts JS dual-op result)
    pae_full = pae_p3db / 100
  Else:
    pout_dbm = pin_dbm + gain_dB
    pae_full = spec PAE / 100

  pout_w    = 10^((pout_dbm - 30) / 10)           [dBm → W]
  pdc_w     = pout_w / pae_full                    [DC power draw]
  pdiss_w   = pdc_w − pout_w                       [heat dissipated]
  tj_c      = ta + pdiss_w × rth                   [junction temp]

  Compression check: if pout_dbm > p1db → WARN, clamp to p1db

  At backoff:
    pout_bo_dbm = pout_dbm − backoff_dB
    pout_bo_w   = 10^((pout_bo_dbm - 30) / 10)
    pdc_bo_w    = pout_bo_w / pae_bo  (PAE degrades at backoff)

  ── Matching Network ────────────────────────────────────────────────
    pout_dbm = pin_dbm − loss_dB

  ── Splitter ────────────────────────────────────────────────────────
    split_loss_dB = 10·log10(n_ways)              [power division]
    pout_dbm = pin_dbm − split_loss_dB − extra_loss_dB

  ── Combiner / Doherty Combiner ─────────────────────────────────────
    Collect all input branch powers:
      inputPowers = [pout_branch_1, pout_branch_2, …]
    Combined = 10·log10( Σ 10^((P_i - 30)/10) ) + 30   [sumdbm]
    pout_dbm  = Combined − combiner_loss_dB
```

### 2.3 Aggregation

```
final_pout_dbm  = power at the terminal output node
total_gain_dB   = final_pout_dbm − input_power_dbm
system_PAE      = final_pout_w / Σ(pdc_w_i) × 100%
total_PDC       = Σ pdc_w_i
total_Pdiss     = Σ pdiss_w_i

Same aggregation repeated at backoff → _bo suffixed fields.
```

### 2.4 Pout = P(X)dB — What This Means

```
P1dB  →  Output power where gain has dropped by 1 dB from linear.
          Most conservative; device is already in light compression.
P2dB  →  Output power where gain has dropped by 2 dB.
P3dB  →  3 dB gain compression. Most common PA datasheet reference.
          Typically ~1–2 dB below Psat.
P5dB  →  5 dB gain compression. Near saturation.

Relationship:  P1dB < P2dB < P3dB < P5dB < Psat
Typical gap:   P3dB ≈ P1dB + 2 dB  (technology-dependent)

The user selects which compression point defines "Pout".
The number entered in spec_p3db / global_pout_p3db is ALWAYS the
operating Pout — the compression point selector is a label/annotation
confirming which physical compression reference it corresponds to.
Downstream calculations use spec_p3db as Pout regardless of label.

P1dB (per component):
  The device's 1 dB compression point.
  Must satisfy:  P1dB ≤ Pout  (P1dB is AT or BELOW operating Pout).
  Violation → compression warning (device pushed into compression).
```

---

## 3. Data Flow Diagram (Simplified)

```
Project Tab
  └─ create_project_btn
       ├─ spec_frequency ──────────────────┐
       ├─ spec_p3db (= Pout) ─────────────┤
       ├─ spec_par  (= PAR) ──────────────┤
       ├─ spec_gain ────────────────────►  syncLineupSpecs (JS)
       ├─ global_frequency               │  currentLineupSpecs = {
       ├─ global_pout_p3db               │    p3db, par, pavg,
       └─ global_backoff / PAR           │    frequency_ghz, gain,
                                         │    compression_point }
Spec Panel changes                       │
  └─ observeEvent(spec_*)              ◄─┘
       ├─ syncLineupSpecs (JS)
       └─ updateNumericInput → Global Lineup Parameters

Calculate button (input$lineup_calculate)
  └─ read components + connections
  └─ lineup_calculate_engine()
       └─ calc_pa_lineup.R
            ├─ topo sort
            ├─ per-stage cascade
            ├─ aggregate results
            └─ generate rationale
  └─ lineup_calc_results() ← store
  └─ updateComponentProperties → JS canvas (props.pout_p3db etc.)
  └─ output$lineup_calc_results → Results panel
  └─ output$pa_lineup_equations_dynamic → Power/Gain/PAE tabs
```

---

## 4. File Map

| File | Role |
|------|------|
| `R/ui.R` | All UI layouts, Spec panel (spec_p3db, spec_compression_point), Global Params, Canvas lower sidebar |
| `R/modules/server/server_pa_lineup.R` | Main PA lineup server: observers, property panel, calculate triggers, equations renderUI |
| `R/modules/calculations/calc_pa_lineup.R` | Pure R calculation engine: topology sort, per-stage cascade, aggregation |
| `R/modules/server/server_global_params.R` | Derived displays (Pavg, Pin), spec↔global sync observer |
| `R/modules/server/server_projects.R` | Project creation → propagates freq/Pout/PAR to specs + globals |
| `R/modules/server/server_guardrails.R` | Technology guardrail plots with device library overlay |
| `R/www/js/pa_lineup_canvas.js` | D3 canvas: component drag/drop, JS power preview, display columns, applySpecsToComponents |
| `R/www/custom.css` | Dark theme, canvas sidebar layout |
| `config/technology_guardrails.yaml` | Technology limits (GaN, LDMOS, GaAs, SiGe, InP) |
| `device_portfolio/*.json` | Saved user devices (used by device library overlay) |
