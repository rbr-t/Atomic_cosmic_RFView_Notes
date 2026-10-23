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

The API batch leaves the original Ropt/gate-width check intact. The separate
full-suite panel is delivered in Batch 6 below. The legacy formatted rationale
function is not yet ported.

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

### Batch 6 - full-stage sizing UI

Expand **Full-stage transistor sizing** below the lineup results. Set a manual
output-power target (dBm), entered PAE (%), supply voltage (V), design frequency
(GHz), topology, substrate relative permittivity and thickness (mm). Results
update reactively through the qualified suite:

- Ropt, gate width and quiescent current.
- Input matching topology, Q, L, C and legacy bandwidth estimate.
- Doherty peak-device Ropt and peak/main gate ratio.
- Combiner impedance, length and width.

Single-ended topology explicitly marks Doherty quantities as **Not applicable**.
Invalid or blank inputs replace the results with an inline error; old successful
results are not left visible. Model assumptions and qualification limits remain
visible with each valid result.

This is an independent session-only calculator, not a selected-canvas-device
editor. Its inputs are not saved in lineup JSON, inferred from the current
lineup, or applied to canvas devices. The original quick sizing check is
unchanged and uses its own knee-voltage/power-density controls; the full suite
retains the fixed legacy GaN assumptions described above.

Chromium tests verify default numeric outputs, single-ended and asymmetric
Doherty behavior, zero frequency, blank power, invalid supply voltage, recovery,
session isolation, narrow layouts and unchanged lineup results. The full suite
continues to pass **422 tests**, with lint and strict type checks.

### Batch 7 - bounded Touchstone parser

[touchstone.py](src/rfview/domain/touchstone.py) provides a pure
`parse_touchstone(text, filename, dataset_tag=None)` API. The filesystem boundary
is `read_touchstone(path, dataset_tag=None)` in
[services.py](src/rfview/services.py). Both raise explicit errors; no Shiny, R,
database or network is needed.

```python
from pathlib import Path
from rfview.services import read_touchstone

network = read_touchstone(Path("measurement.s2p"))
print(network.freq_ghz, network.z0)
print(network.points[1].param)  # S21, not S12
```

Current scope:

- Touchstone 1.x `.s1p`/`.s2p`, RI/MA/DB, Hz/kHz/MHz/GHz and scalar positive
  reference impedance.
- Full-line/inline comments, wrapped records, BOM and scientific notation.
- Typed immutable results with GHz frequencies and long-form parameter points:
  real/imaginary, linear/dB magnitude, phase in degrees and dataset tag.
- Legacy-compatible GHz/MA/50-ohm defaults when no option line is supplied;
  zero magnitudes use the legacy -300 dB display floor.
- Explicit 5 MiB and 100,000-frequency limits.

Three synthetic file fixtures are compared against the active R parser,
including an asymmetric two-port case that verifies S11/S21/S12/S22 ordering.
Forty focused tests cover conversion, record wrapping, units, defaults, limits
and malformed input. The full Python suite now has **462 passing tests**.
The optional [R exporter](tests/reference/export_touchstone.R) freezes numeric
references and source/fixture fingerprints; normal tests do not require R.

Intentional validation improvements: bad numeric tokens, nonfinite values,
incomplete tails, duplicate/late options, nonpositive reference impedance,
negative MA magnitudes and nonincreasing frequencies fail rather than being
silently discarded or producing partially parsed success.

**Not delivered in the parser batch:** upload/viewer UI (added in Batch 8),
Touchstone 2.x keyword sections, three or
more ports, noise blocks, per-port reference impedances, non-S parameters,
S-to-Z/Y/H conversion and export. Unsupported keyword sections and formats are
rejected. The legacy parser labels all multiport values column-major and
ignores 2.x keywords; the new parser deliberately does not reproduce those
claims until separately qualified.

This API preserves short fixture-style filename tags; it does not reproduce
the legacy automatic shortening of filenames longer than 32 characters.
No existing application upload limit is changed by this bounded API.

### Batch 8 - Touchstone upload and magnitude/phase viewer

Expand **Touchstone magnitude and phase viewer** below the lineup results.
Upload a supported `.s1p`/`.s2p` file, then select an available S-parameter.
The panel shows filename, port count, reference impedance, record count,
frequency range and data representation, plus magnitude (dB) and wrapped phase
(degrees) on linear frequency axes (GHz). Single-record datasets render a
visible marker; negative dB and phase values remain within chart bounds.

The viewer is deliberately capped at **2,000 frequency records** and 5 MiB.
This keeps rendering bounded without hidden decimation; the parser API retains
its separate 100,000-record limit. Unsupported/oversized uploads are rejected
explicitly and leave the last valid dataset visible with a retention notice.
The original upload filename, not the server's temporary filename, determines
the port count.

Datasets and parameter choices are session-local, independent of the lineup,
and not saved in lineup JSON. One-port uploads expose only S11. New sessions
start without an uploaded network. This does not yet include Smith charts,
dataset overlays, phase unwrapping, zoom/pan, numeric hover, parameter conversion
or export, calibration checks, noise data, Touchstone 2.x or multiport support.

The full suite now has **466 passing tests**. New renderer tests cover signed
axis bounds, single-record markers, escaping, upload filenames and viewer
limits. Chromium workflows cover actual uploads, parameter selection, rejected
upload retention, two-port-to-one-port switching, session isolation, responsive
widths and preserved lineup/sizing behavior.

### Batch 9 - two-port S-to-Z/Y conversion APIs

[network_parameters.py](src/rfview/domain/network_parameters.py) exposes pure
`s_to_z(s, z0=50)` and `s_to_y(s, z0=50)` functions with no new dependencies.
Supply a 2-by-2 **row-major** sequence of complex values:

```python
from rfview.domain.network_parameters import s_to_z, s_to_y

s = ((0.1 + 0.2j, 0.03 + 0.04j), (2 - 0.5j, -0.2 + 0.1j))
z = s_to_z(s, z0=75)  # ohms
y = s_to_y(s, z0=75)  # siemens
```

Rows are `(S11, S12)` and `(S21, S22)`, which differs from Touchstone's serialized
S11/S21/S12/S22 order. Results are immutable nested tuples in the same
row/column order. Inputs are not mutated. Only a common, real, finite positive
reference impedance is supported; no per-port or complex reference impedance,
renormalization, multiport conversion or automatic network-wide conversion is
implied.

Eighteen R-reference cases cover matched, diagonal, reciprocal, asymmetric and
near-singular networks at 25/50/75 ohms. Both output matrices match at
`rtol=1e-10`, `atol=1e-12`. Additional tests verify the Z/Y inverse identity,
Touchstone orientation, finite numeric/shape checks and overflow rejection.
Determinant magnitude below `1e-15` raises an explicit conversion error,
replacing legacy NA matrices while preserving the legacy threshold.
This absolute threshold is not a full numerical condition-number assessment.

The full suite now has **536 passing tests**. This API batch is followed by the Z/Y viewer slice below. Complex
results require explicit real/imaginary serialization if exported as JSON.
The optional [R exporter](tests/reference/export_network_parameters.R) generates
the frozen comparison matrices; Python runtime/tests do not require R.

### Batch 10 - Z/Y viewer controls

In the Touchstone viewer, choose **Network representation**:

- **S** retains magnitude (dB) and wrapped phase (degrees).
- **Z** shows real/imaginary impedance in **ohms**.
- **Y** shows real/imaginary admittance in **siemens (S)**.

The S-parameter selector retains row/column indices: choosing S21 with the Z
representation displays Z21, not Z12. Conversion uses the uploaded scalar
reference impedance and the qualified two-port APIs. Dataset values, upload
state and lineup calculations are not changed. Representation is session-local.

Only two-port datasets support conversion in this slice. For a one-port
dataset, Z/Y shows an explicit error and offers recovery by selecting S.
If any frequency is singular or numerically invalid, the entire converted view
is replaced by an error naming that frequency in GHz; no points are dropped and
no misleading partial curve is rendered. The original S dataset remains
available. The viewer retains its 2,000-record limit and does not certify
conditioning, passivity or calibration integrity.

The full suite now has **543 passing tests**. Converted-coordinate tests compare
SVG points to the qualified numerical results, and cover units, unsupported
views and singular-frequency reporting. Browser workflows verify Z/Y switching,
singularity recovery, one-port rejection, session defaults and preserved
upload/lineup/sizing behavior.

### Batch 11 - bounded reflection Smith chart

Select **Smith impedance chart (S11/S22)** in Network representation, then
choose S11 or (for two-port datasets) S22. The responsive SVG shows a normalized
impedance grid, unit-circle boundary and a frequency-ordered reflection trace
with visible markers, including a single-record dataset.

The center is matched, left boundary is short, and right boundary is open.
Positive reactance lies above the real axis. The grid uses normalized resistance
`r = 0.2, 0.5, 1, 2, 5` and reactance
`x = +/-0.2, +/-0.5, +/-1, +/-2, +/-5`, normalized to the uploaded reference
impedance. Native marker tooltips identify frequency in GHz and complex Gamma.

S21/S12 transmission data are explicitly rejected in this view. If a selected
reflection point exceeds the unit circle (`|Gamma| > 1 + 1e-12`), an error names
its frequency, and no partial/clipped trace is shown. The source dataset remains
available through S magnitude/phase. A displayed trace inside the circle does
**not** establish full-network passivity, stability or calibration integrity.

The existing 2,000-record viewer limit remains. This is an impedance grid, not
an admittance Smith grid; no matching-element synthesis, movable markers,
multi-dataset overlays, zoom/pan or chart export is included.

The full suite now has **548 passing tests**. Tests verify known
short/match/open/positive/negative-reactance coordinates, resistance-circle
geometry, reactance-locus bounds, single-point visibility, input preservation,
unsupported parameters and out-of-circle errors. Browser workflows verify
one-/two-port Smith views, error recovery and responsive layouts while retaining
the existing S/Z/Y and lineup behavior.

### Batch 12 - legacy two-port stability/gain metrics API

[stability.py](src/rfview/domain/stability.py) exposes pure
`stability_metrics(s)` for a row-major 2-by-2 S-matrix. Its typed, JSON-safe
result includes determinant magnitude, Rollett K, input/output mu, B1, legacy
MSG/MAG estimates, the legacy stable flag, a model identifier and warnings.
Shared matrix validation is reused by the S-to-Z/Y APIs.

```python
from rfview.domain.stability import stability_metrics

metrics = stability_metrics(((0, 0.1), (2, 0)))
assert metrics.K == 2.6
print(metrics.model_version, metrics.warnings)
```

**Engineering caveat:** the active R implementation uses `20*log10` for
MSG/MAG power-gain expressions rather than conventional `10*log10`. This API
is explicitly `legacy-r-stability-v1`; it reproduces that scale and attaches a
warning to every result. Do not interpret these fields as corrected power gain.
MAG uses an algebraically equivalent reciprocal expression to avoid
cancellation at large K. Correcting the gain convention requires a separately
versioned change with engineering acceptance.

The legacy `stable` flag is reproduced as K > 1 and mu_in > 1, including R's
infinite-K behavior when coupling is negligible. It is not a complete
measurement/stability certification. Undefined/unbounded K and undefined mu or
gain fields are `None` with explicit diagnostics, rather than JSON Infinity/NA.
The legacy denominator threshold of `1e-15` is retained. Bad matrix shapes,
nonfinite values and numeric overflow raise errors.

Eight R-reference cases cover matched, unilateral, asymmetric, unstable,
boundary, active-reflection, zero-forward and negligible-reverse networks.
Independent checks verify known metrics, undefined cases and cancellation-safe
large-K behavior. The full suite now has **566 passing tests**.

This batch is API-only: no stability plot, stable/unstable UI badge or stability
circles are yet added. Normal Python runtime/tests do not require R; the
[reference exporter](tests/reference/export_stability.R) is optional.

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
