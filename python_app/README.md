# RF Engineering Platform - Python migration

This is the first runnable migration slice, not a complete replacement of the
workspace. The legacy R sources remain unchanged and are **not archived yet**.
The application and its normal tests run without R or RStudio.

## Setup and run (Windows PowerShell)

Requirements: Python 3.13, Node.js/npm, and this repository checkout. Run from the
repository root:

```powershell
py -3.13 -m venv python_app\.venv
.\python_app\.venv\Scripts\python.exe -m pip install -r python_app\requirements.lock
.\python_app\.venv\Scripts\python.exe -m pip install --no-deps -e python_app
Push-Location python_app
npm ci --ignore-scripts
Pop-Location
.\python_app\.venv\Scripts\python.exe -m shiny run --host 127.0.0.1 --port 3840 python_app\src\rfview\app.py
```

Open <http://127.0.0.1:3840/>. Stop with Ctrl+C.
This is an unauthenticated, localhost-only development preview, not a production
deployment. State is session-only; download JSON to retain work.

The package intentionally serves the original D3 canvas from the repository and
D3 from the local npm installation. Installing the Python wheel alone is not a
standalone deployment. No CDN is needed by the migration adapter.

## Delivered scope

| Area | Current behavior |
|---|---|
| Calculations | Pure Python lineup cascade, parallel splitting/combining, full-power/backoff results, phase, efficiency and thermal summaries |
| Supporting calculations | Transistor sizing, matching, propagation/link budget, passive loss, gain/backoff primitives and selected RF tools |
| Canvas | Retained D3 renderer, movement, wiring, add transistor, selection, basic transistor editing, undo/redo |
| Documents | JSON load/save preserving IDs, edges, transforms, extra fields and saved operating-point settings |
| Validation | Explicit malformed/cyclic/unsupported graph errors; finite numeric validation; 5 MiB JSON limit |
| Isolation | Independent reactive document and result state per browser session |
| Technology guardrails | Typed YAML loading, pure device validation and an explicit selected-transistor advisory |
| Qualification | Frozen R numeric references, Python contracts, static checks and browser workflow regression |

The UI offers a subset of legacy property controls and a single canvas. Full
multi-canvas lifecycle and full property editing remain to be migrated.

### Accuracy and legacy assumptions

The frozen oracle contains 11 lineup cases and 181 scalar cases exported from
the current R implementation. Numeric parity tests use relative tolerance
`1e-10` and absolute tolerance `1e-12`. These demonstrate reproducibility of
covered cases, not universal RF-model accuracy or whole-app parity.

Results identify their model as `legacy-r-v1`. Deliberately retained assumptions:

- Legacy summed gain includes both parallel branches; the UI also shows the
  aggregate net gain separately.
- Entered efficiency drives the legacy DC-power calculation; PAE/DE labels and
  model limitations must be considered when interpreting results.
- Outputs are limited using the legacy P1dB model. Phase accumulation follows
  legacy traversal rather than a coherent per-path RF simulation.
- By default the UI recomputes from system input and gain. Opt into saved browser
  operating points only to reproduce legacy dual-operating-point values.
- Gate-width sizing follows current R source, not an inconsistent older test.

Unequal split ratios and unsupported branching are rejected explicitly rather
than producing plausible-looking results. MTTF/reliability is not ported.

### Batch 2 - technology guardrail validation

The application loads the existing
[technology catalog](../PA%20design%20App/config/technology_guardrails.yaml)
without modifying it. Missing, unsafe or malformed YAML fails explicitly; there
is no embedded fallback catalog. Domain calculations do not read files or import
Shiny/YAML; the service boundary handles loading.

Select a transistor, expand **Technology guardrail advisory**, and explicitly
choose a technology. The panel checks applied component properties at the
advisory frequency and optional power density. Technology/frequency/density
choices are session-only advisory inputs, not saved design properties; they do
not change lineup results or block edits.

The port reproduces the active R checks for operating range/sweet spot,
frequency-dependent available gain, practical PAE, absolute supply voltage and
optional power density. It preserves strict `>` thresholds: density exactly at
the maximum warns rather than errors, matching the executable R code despite
the YAML comment saying "at or above".

The reference fixture covers **132 R cases** across all six technologies,
including exact boundaries, just-over-boundary values and combined errors.
The guardrail-validation batch reached **374 passing tests**. The browser test
also verifies OK/error advisories and unchanged lineup results.

This is a legacy-model advisory, not a safety certification or a general
Class-B physical-limit assertion. The existing R validator does **not** evaluate
output power, thermal limits, compression, minimum supply voltage or the YAML
breakdown/reliability derating factors. The Python port does not silently invent
those checks. Invalid/nonfinite parameters and unknown technologies are rejected.
Malformed catalog ranges/margins are rejected before calculations.

Public entry points:

- [read_guardrails](src/rfview/services.py): safe YAML loading into a typed catalog.
- [DeviceParameters / validate_device_params](src/rfview/domain/guardrails.py):
  pure validation with explicit status, diagnostics, available gain and PAE limit.
- [export_guardrails.R](tests/reference/export_guardrails.R): optional offline
  regeneration of the additional R oracle. Normal Python tests do not require R.

### Batch 3 - guardrail plot and summary data

Four pure, typed row builders are available in
[guardrails.py](src/rfview/domain/guardrails.py), without pandas, UI, storage or
network dependencies:

| Function | Default output across six technologies |
|---|---|
| `build_design_space_data` | 360 rows; 60 log-spaced frequencies per technology |
| `build_gain_bandwidth_data` | 676 rows; typical/maximum gain and operating-range flags |
| `build_pae_backoff_data` | 1,950 rows; classes A/AB/B/Doherty/F, 0-16 dB in 0.25 dB steps |
| `build_guardrail_summary_table` | Six rows with legacy column labels and engineering units |

Technology ordering, color metadata, row fields, Boolean flags and numerical
values are compared against complete R-generated output in
[guardrail_builders_reference.json](tests/fixtures/guardrail_builders_reference.json).
Single-point and three-point design-space sampling are also qualified. Numeric
tolerances remain `rtol=1e-10`, `atol=1e-12`. Sample counts must be positive
integers; malformed inputs raise errors rather than returning empty success.
Optional legacy fields retain builder-specific defaults; absent summary values
are `None` (JSON `null`).

Intentional presentation adaptation: summary power-density ranges use **two**
decimal places rather than R's one. This preserves the SiGe minimum of
**0.05 W/mm**, which the R summary displays as `0.0`. The oracle stores both the
original summary and separately calculated two-decimal density labels.
Underlying numerical data is unchanged.

The data-builder batch reached **388 passing tests**.

### Batch 4 - technology charts and summary UI

Expand **Technology charts and summary** below the lineup results to view:

- Typical power density versus logarithmic frequency.
- Typical and maximum available gain versus logarithmic frequency.
- PAE versus output backoff for a selected PA class.
- A horizontally scrollable technology summary with units in column headings.

Choose all technologies or one technology; choose A/AB/B/Doherty/F for the
backoff chart. Filters are session-local and independent of the lineup and
device advisory. Chart generation reuses the qualified builders without adding
dependencies. The SVG views have labelled axes, accessible image descriptions,
native trace-name tooltips, technology-color legends and dashed maximum-gain
traces. Summary regions support keyboard focus and scrolling.

This is a deliberate initial presentation adaptation, **not full visual parity**:
the legacy multidimensional bubble view is represented by a 2D density envelope,
with PAE and gain in separate charts. No point picking, numerical hover readout,
zoom/pan or chart export is implemented yet. The envelopes remain legacy
empirical estimates, not measurements or qualified operating limits.

The suite now has **393 passing tests**, including SVG coordinate/shape/unit
checks, escaping and invalid-filter checks. Chromium workflow checks cover
all/single-technology filtering, PA-class changes, visible charts at 375/768/1440
pixel widths and unchanged lineup behavior.

### Adapter boundary

[canvas_adapter.js](src/rfview/www/canvas_adapter.js) waits for Python Shiny's
session initialization before loading the unchanged legacy script. A temporary,
name-specific compatibility shim adapts the legacy zero-argument `reinit_sticky`
handler to Shiny's one-argument contract. JSON restoration uses the canvas history
restore primitive to preserve identities and geometry. Python results do not
overwrite saved model inputs.

### Batch 5 - full-stage transistor sizing orchestration

[transistor.py](src/rfview/domain/transistor.py) now exposes typed
`StageSizingInput` and pure `transistor_design_suite`. The orchestrator reuses
the previously qualified Ropt, gate-width, bias-current, Doherty, matching and
combiner primitives instead of duplicating their equations.

```python
from rfview.domain.transistor import StageSizingInput, transistor_design_suite

stage = StageSizingInput(pout_dbm=40, pae_pct=55, vdd_v=28)
design = transistor_design_suite(stage, freq_ghz=3.5, topology="doherty_symmetric")
assert design["ropt"]["Ropt_ohm"] == 33.8
assert design["gate_width"]["gate_width_mm"] == 4
```

Supported topologies: `single_ended`, `doherty_symmetric`,
`doherty_asymmetric_6dB`, `doherty_asymmetric_9dB`. Single-ended designs return
`None` for Doherty sizing and the combiner. Results include all nested numeric
and structural fields from the legacy suite, excluding formatted formula prose,
plus a model identifier and explicit limitations.

Sixteen frozen R-reference cases cover defaults, power/supply/substrate changes,
unity and clamped input matching, and efficiency extremes. All nested outputs
match at `rtol=1e-10`, `atol=1e-12`. Invalid parameters/topologies raise errors;
the port does not reproduce legacy NA/default-shaped error returns.
The suite now has **422 passing tests**.

This is an API-level batch: the existing sizing UI still shows its original
Ropt/gate-width check. The full design-suite panel and human-readable rationale
formatter are not yet migrated.

The suite intentionally retains R's hard-coded GaN assumptions: knee voltage
2 V, power density 2.5 W/mm, maximum current density 800 mA/mm, conduction angle
240 degrees, and gate-input resistance approximated as `max(Ropt / 5, 1 ohm)`.
Combiner length uses bulk relative permittivity rather than effective
microstrip permittivity. These are preliminary synthesis estimates, not
device-model or EM-qualified designs.

Calculation inventory after this batch:

| Legacy calculation surface | Python status |
|---|---|
| Frequency planning, passive loss, link budget | Scalar APIs and R references present |
| Lineup cascade | Qualified compatibility engine; workflow expansion remains |
| Guardrail validation and four row builders | Qualified APIs with advisory/charts UI |
| Transistor primitives and full-stage suite | Qualified APIs; full-suite UI/rationale pending |
| Power, wavelength, S11, thermal tools | Qualified scalar APIs; dedicated tools UI pending |
| Constant-hazard reliability curve | Not yet ported |
| Arrhenius MTTF | Deferred: legacy multiplier makes lifetime increase with temperature |

The MTTF issue must be resolved as an explicitly versioned engineering change,
not silently corrected inside a legacy-parity port. The remaining runtime,
parser, persistence, AI/KB and document migrations are still required.

## Validation

From the repository root:

```powershell
.\python_app\.venv\Scripts\python.exe -m pytest python_app\tests -q
.\python_app\.venv\Scripts\python.exe -m ruff check python_app\src python_app\tests
.\python_app\.venv\Scripts\python.exe -m mypy --config-file python_app\pyproject.toml python_app\src
node --check python_app\src\rfview\www\canvas_adapter.js
.\python_app\.venv\Scripts\python.exe -m pip check
```

For browser checks, keep the preview running in another terminal:

```powershell
.\python_app\.venv\Scripts\python.exe -m playwright install chromium
.\python_app\.venv\Scripts\python.exe python_app\tests\browser_smoke.py http://127.0.0.1:3840
```

Alternatively pass `--channel msedge` or `--channel chrome` to use an installed
browser. The smoke test checks calculation, guardrail advisories, editing, undo/redo, actual JSON
download/upload, settings restoration, independent sessions, rejected uploads
and horizontal overflow at widths 375, 768 and 1440 pixels.

[CI](../.github/workflows/python-migration.yml) defines Windows/Linux regression
and static checks, plus Linux Chromium smoke coverage. Hosted CI has not been
verified merely by running these checks locally.

R is only needed to intentionally regenerate the
[reference fixture](tests/fixtures/legacy_reference.json) using
[export_legacy.R](tests/reference/export_legacy.R). Review source changes and
engineering expectations before updating this oracle; never refresh it merely
to silence a mismatch.

## Remaining migration batches

Each batch should deliver runnable behavior, targeted tests and a scope update:

1. Complete remaining calculations and legacy property controls; qualify advanced chart interactions separately.
2. Migrate load-pull and Touchstone parsers with frozen file fixtures and viewers.
3. Add project persistence, snapshots and multi-canvas lifecycle.
4. Integrate AI/KB and the existing guarded Python ingestion pipeline.
5. Qualify integrated and standalone RF CAD separately.
6. Convert education/manual/IFX documents and Web Page Knitter to Python-executed
   builds, retaining their interactive assets.
7. Package deployment; measure performance/capacity; qualify data conversion and
   rollback; conduct whole-workspace user acceptance.

Only archive R after the final acceptance gates pass. Numeric reproducibility
does not establish visual, workflow, file, AI or performance parity.
See the [workspace migration assessment](../PYTHON_MIGRATION_REVIEW.html) for the
broader scope, effort estimate and retirement gates.
