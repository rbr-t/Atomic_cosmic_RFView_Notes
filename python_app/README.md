# RF Engineering Platform - Python migration

This is a runnable, incrementally qualified migration, not a complete replacement of the
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
deployment. State starts session-only; use **Save as new project** / **Save new
snapshot** for explicit local persistence, or download JSON to retain work.

The package intentionally serves the original D3 canvas from the repository and
D3 from the local npm installation. Installing the Python wheel alone is not a
standalone deployment. No CDN is needed by the migration adapter.

## Delivered scope

| Area | Current behavior |
|---|---|
| Calculations | Pure Python lineup cascade, parallel splitting/combining, full-power/backoff results, phase, efficiency and thermal summaries |
| Supporting calculations | Transistor sizing, matching, propagation/link budget, passive loss, gain/backoff primitives and selected RF tools |
| Canvas | Retained D3 renderer, all six component types, movement/wiring, validated calculation inputs and design metadata/pose, undo/redo, four session slots, confirmed copy/clear and simultaneous read-only comparison |
| Documents | Single-lineup JSON preserving IDs/edges/extra fields/operating points; separate four-lineup workspace bundle |
| Local projects | Single-user SQLite projects, immutable snapshot revisions, optimistic conflict detection and confirmed four-canvas/operating-point recovery |
| RF network tools | Touchstone 1.x/2.0 for 1-9 ports; full/triangular matrices, explicit mixed-mode transforms, v1/v2 noise table/plot; S/Smith and two-port conversions/stability; source/transformed and converted-family export |
| Load-pull | Eight explicit ASCII adapters, normalized measurements/JSON export, sweep selection, measured Gamma plots and piecewise-linear contour estimates |
| Standalone RF-CAD interchange | Bounded JSON v1.0 import, document summary, position overview and normalized export; session-only and separate from the PA lineup; no geometry editing |
| Corrected model options | Explicit conventional power gain v2 and generic Arrhenius/constant-hazard lifetime v2, separate from legacy-compatible lineup results |
| Validation | Explicit malformed/cyclic/unsupported graph errors; finite numeric validation; 5 MiB JSON limit |
| Isolation | Independent reactive document and result state per browser session |
| Technology guardrails | Typed YAML loading, pure device validation and an explicit selected-transistor advisory |
| Device knowledge base | Read-only local search of checked-in vendor records with frequency/manufacturer/technology filters and source-file SHA-256 provenance |
| Qualification | Frozen R numeric references, Python contracts, static checks and browser workflow regression |

The UI offers four tabbed session editors plus simultaneous read-only topology/
result comparisons. Calculation properties, descriptive metadata and pose are
editable. Comparison diagrams are simplified, not four simultaneous legacy
editors. Full legacy property/display/synthesis controls, simultaneous editable
layouts and production multi-user lifecycle/RBAC remain acceptance gaps.

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
than producing plausible-looking results. The separately versioned generic
lifetime model below corrects the R temperature-acceleration direction; it
does not establish manufacturer-calibrated reliability or alter lineup results.

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

The MTTF issue was subsequently addressed by the explicitly versioned generic
model in batch 21, not silently corrected inside the legacy-parity port.
The remaining runtime,
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

This batch is API-only; Batch 13 adds a numeric viewer. Stability plots and
circles are not included. Normal Python runtime/tests do not require R; the
[reference exporter](tests/reference/export_stability.R) is optional.

### Batch 13 - Touchstone stability table

In the Touchstone viewer, choose **Two-port stability / legacy gain metrics**.
The frequency-indexed table displays determinant magnitude, K, input/output mu,
B1, legacy MSG/MAG (dB) and the legacy stable flag. It uses the complete network,
independent of the S-parameter selector; no uploaded values or lineup settings
are changed. The existing 2,000-frequency viewer limit remains in force.

The model identifier and gain-scale/stability-certification warnings remain
visible above the table. Undefined metrics are explicitly labelled, including
the legacy infinite-K case, rather than omitted or rendered as zero. Warnings
explain the undefined cases. A false legacy flag is not labelled as proof of
instability, and a true flag is not labelled as safety certification.

One-port data is explicitly rejected for this view; choose S to recover.
Numerical failures replace the whole table with a frequency-specific error,
leaving the source network available. No partial table or silent decimation is
used. The table has labelled row/column headers and a keyboard-focusable
horizontal scroll region, reusing the existing responsive table styling.

The full Python suite now has **569 passing tests**. Renderer tests compare all
displayed metrics with the qualified API, verify frequency/matrix orientation,
parameter independence, undefined values, unchanged source data, one-port
rejection and numeric-failure recovery. Chromium regression verifies view
switching, parameter independence, one-port rejection and table containment at
375/768/1440 px, alongside the existing lineup/upload/sizing/session workflows.
No stability circles, corrected
power-gain model, dataset overlays or export are delivered in this slice.

### Batch 14 - pure two-port stability-circle API

`stability_circles(s)` in [stability.py](src/rfview/domain/stability.py) returns
typed load/output and source/input circle centers and radii in their respective
complex reflection-coefficient planes. Supply row-major `(S11, S12), (S21, S22)`
values, as for the other two-port APIs:

```python
from rfview.domain.stability import stability_circles

circles = stability_circles(((0, 0.1), (2, 0)))
assert circles.load is not None
assert abs(circles.load.radius - 5) < 1e-12
print(circles.model_version, circles.warnings)
```

The version is `legacy-r-stability-circles-v1`. Each defined circle has finite
`center_r`, `center_i` and nonnegative `radius`, all dimensionless. Centers and
radii match the active R `sp_stab_circles` formulas. Input matrices are not
mutated. Each port is evaluated independently: a denominator magnitude at or
below `1e-15` yields `None` for that circle with a port-specific warning,
not a fabricated zero-radius circle. Line/degenerate boundaries at that
threshold are not represented by this finite-circle API. Actual zero-radius
results are retained, with an explicit degeneracy caveat.

Circle geometry alone does **not** identify the stable side or certify network
stability. No clipping to the passive unit disk or automatic stable-region
classification is performed. Invalid/nonfinite matrices and numerical overflow
raise errors rather than produce partial results.

Eight frozen R-reference cases cover matched, unilateral, asymmetric, unstable,
boundary, active-reflection, zero-forward and negligible-reverse networks.
Independent tests verify known centers/radii, unit-reflection identities at
16 points on each source/load boundary, separately undefined ports, threshold
behavior, input preservation and JSON-finite output.
The full Python regression suite now has **589 passing tests**; lint,
formatting, strict source typing and Python syntax checks pass.
This slice is API-only; viewer circles and frequency selection remain separate.
The optional [R exporter](tests/reference/export_stability_circles.R) reuses the
qualified stability input matrices; normal Python tests do not require R.

### Batches 15-19 - RF views, source export and canvas workflows

These independently tested slices advance both the RF-data and canvas
workstreams; they do **not** complete either workstream.

#### 15. Selected-frequency stability-circle viewer

Choose **Source / load stability circles**, then an uploaded frequency. The
complete two-port matrix supplies separate load/source boundaries, regardless
of the S-parameter selector. Undefined finite circles show the API warnings.
Each plot scales independently to show the **entire** circle, including
regions outside the passive unit disk. The dashed unit circle and a center
marker supply context; they do not classify either side as stable. This is a
complex-Gamma plane, not a Smith impedance grid. No clipping, region shading,
stable-side inference or stability certification is performed.

#### 16. Remaining legacy two-port conversion families

[network_parameters.py](src/rfview/domain/network_parameters.py) now supplies
`s_to_h`, `s_to_abcd` and `s_to_t`, using the active R conventions and
singularity thresholds. Corresponding views plot real/imaginary values:

| View | Selector mapping | Units |
|---|---|---|
| h | S11/S12/S21/S22 -> h11/h12/h21/h22 | ohm / dimensionless / dimensionless / S |
| ABCD | S11/S12/S21/S22 -> A/B/C/D | dimensionless / ohm / S / dimensionless |
| T | S11/S12/S21/S22 -> T11/T12/T21/T22 | dimensionless |

ABCD uses `[V1,I1] = ABCD [V2,-I2]`. Scattering transfer T uses
`[b1,a1] = T [a2,b2]`; these are **different** matrices. Hybrid conversion
intentionally follows R via Z and rejects a singular Z intermediate, even
where another formulation might yield finite hybrid parameters. No partial
frequency curves are rendered on conversion failure. One-port conversion is
still unsupported. The 18 existing input matrices/reference-impedance cases
are independently exported for each new family, with null R results requiring
explicit Python errors. Independent voltage/current and wave equations,
through-network identities and threshold tests supplement the R comparisons.

#### 17. Source Touchstone export

After upload, **Download source S (GHz / RI)** exports one/two-port Touchstone
1.x using the source complex S values and scalar reference impedance. Export
uses 17-digit precision and standard S11/S21/S12/S22 serialization for two
ports. It does **not** export the selected converted view, nor preserve
original comments, formatting, frequency units, dataset tags or RI/MA/DB text.
Round-trip tests preserve every source frequency and complex value. Malformed
records or output exceeding the existing 5 MiB limit fail explicitly.

#### 18. Validated canvas calculation-property controls

Selecting matching, splitter or combiner components exposes insertion loss.
Offset lines also expose phase (degrees) and characteristic impedance (ohms).
Transistors retain the original gain/efficiency/P1dB controls and additionally
expose supply voltage and thermal resistance. Terminations explicitly have
no editable calculation inputs in this model.

Edits use the existing Shiny custom-message/snapshot/history protocol.
Unrelated legacy properties are retained. Negative losses/thermal resistance,
nonpositive supply/impedance, efficiency outside `(0,100]`, blanks and
nonfinite values are rejected **before** changing the canvas. The component-ID
form guard rejects a stale selection. This deliberately tightens validation
of UI edits; it does not silently change imported legacy data or model formulas.
Splitter/combiner branch counts remain graph-derived, not editable counts.
Unequal splitting, complete topology/device/geometry editors and automatic
engineering-model corrections remain out of scope.

#### 19. Four independent session canvas slots

**Active session canvas** switches between four tabbed lineups without
discarding the others. Each slot retains its own components, connections,
metadata, undo/redo history, ID counter and viewport zoom during the session.
Switching clears selection and invalidates calculated results/prepared
downloads. Loading a single-lineup JSON or the example replaces only the
active slot. Slots are isolated between browser sessions.

Use **Prepare workspace download**, then **Download four-canvas workspace**,
to preserve all four lineups in a validated `rfview-workspace-v1` bundle.
**Load four-canvas workspace JSON** restores all slots and the active slot;
invalid uploads retain the current workspace. The bundle is distinct from
legacy single-lineup JSON, which remains supported and exports only the active
lineup. The workspace limit is 5 MiB total, with the existing graph/schema
limits applied to each slot.

Operating-point controls are **shared** between slots in this slice. Workspace
bundles preserve existing per-lineup metadata but do not capture the current
shared controls, undo history, viewport zoom, RF uploads or calculated results.
Imported workspaces restart histories and zoom; ongoing session switching
retains them. At this batch there was no server persistence or cross-session
recovery; batch 32 adds explicit local project snapshots. Simultaneous editable
comparison, cross-canvas wiring and canvas deletion remain outside this slice.

Qualification: **710 passing Python tests**, strict source typing, Ruff and
JavaScript syntax checks. Chromium workflows exercise the RF views, frequency
selection, actual source download/re-import, validated passive edits,
independent canvas switching/undo, workspace download/re-import and session
isolation, alongside the existing lineup/sizing workflows. RF circle/table
views and the full page are checked at 375/768/1440 px.

### Batch 20 - load-pull adapters, measured views and contours

Expand **Load-pull measurements and contours**. Choose the adapter and efficiency
units, select a file, then explicitly import/reparse it. Changing these choices
does not reinterpret an already loaded dataset until import is requested.
Rejected imports retain the last valid dataset with an error notification.
Nothing is written to the legacy datasets or retained after the session.

[loadpull.py](src/rfview/domain/loadpull.py) supports the following bounded
ASCII dialects, not every historical vendor revision:

| Adapter | Qualified dialect / evidence |
|---|---|
| SPL | Cartesian/combined Gamma headers, repeated headers, per-block frequency metadata and explicit VALID=0 exclusion |
| Focus | CCMT-style metadata, header and numeric table |
| LPCWAVE | Load-point Gamma descriptors and numeric measurement rows |
| MDF | Numeric Sweep/Data blocks; string columns explicitly rejected |
| AMCAD | Numeric CSV with supported aliases |
| Anteverta | Numeric CSV with supported aliases |
| MDIF | Variable/data blocks and numeric measurements |
| CST | Peak voltage-wave adapter, independently tested; not R-parser parity |

Seven synthetic vendor cases match frozen active-R output at `rtol=1e-10`,
`atol=1e-12`, with source/fixture revision checks. These fixtures establish
covered dialect parity, **not** acceptance of arbitrary customer files.
Representative real files and additional revisions still need qualification.
The optional [R exporter](tests/reference/export_loadpull.R) regenerates
[loadpull_reference.json](tests/fixtures/loadpull_reference.json); normal tests
do not run R.

Efficiency units are explicitly **percent** or **fraction**; the parser never
guesses from the value range. Numeric extra columns are retained. Optional
missing values remain null; malformed/ragged/ambiguous records fail explicitly.
Power/current/DC/efficiency derivations use available quantities. Negative or
out-of-range measurements, PAE greater than DE, active Gamma and nonpositive DC
power are retained with diagnostics, not clipped or silently repaired.
Rows explicitly marked VALID=0 are excluded with a reported count.
Per-block frequency is retained on each row instead of relabelling all rows
with the final frequency, a documented adaptation from legacy SPL behavior.

The active R CST adapter fails by calling a two-argument normalizer with three
arguments. Its wave-power path also reuses source impedance for the output.
The Python adapter instead uses distinct port references and independently
tested peak voltage-wave equations:

```text
Pin  = (|a1|^2 - |b1|^2) / (2 Z0source)
Pout = (|b2|^2 - |a2|^2) / (2 Z0load)
```

It does not clamp negative power or fabricate dBm/gain for nonpositive power.
Fundamental-row frequency mismatch/harmonic rows are rejected, not mixed into
fundamental results. Confirm instrument normalization and calibration before
engineering use; this adaptation is not a universal CST interpreter.

Select a frequency/input-power/source-Gamma/bias sweep and metric to inspect
measured points and a unit-labelled numeric table. Optional contours use
SciPy Delaunay triangulation with piecewise-linear triangle intersections.
Analytic planar-surface tests verify contour coordinates and no extrapolation
outside the measured convex hull. There is no smoothing or optimum-load
certification; triangles can span unmeasured gaps. Duplicate/collinear
coordinates, undefined metrics, omitted triangulation points and unsupported
numeric ranges fail rather than averaging, dropping points or extrapolating.
Measured-point view remains available when contour assumptions do not hold.

Imports are limited to 5 MiB / 100,000 points; the UI accepts at most 2,000 total
points without decimation. Contour APIs accept 1-20 levels; the UI supplies
five interior levels. Downloads contain **normalized JSON**, including extras,
metadata and warnings, not reconstruction of vendor-specific source syntax.
SciPy and NumPy are included in the pinned Python dependency lock.

### Batch 21 - explicitly corrected gain and lifetime hypotheses

The legacy stability table and lineup engine remain unchanged. Choose
**Conventional power gain v2 (10 log)** for `conventional-power-gain-v2`:

- MSG expression: `10 log10(|S21/S12|)`, without the legacy forward-gain floor.
- MAG is available only for `K > 1` and `|Delta| < 1`, with numerically stable
  evaluation of the `K - sqrt(K^2-1)` factor.
- Undefined/unsupported transmission and stability conditions are labelled,
  not converted into finite gain or a stability certification.

Expand **Generic lifetime hypothesis (corrected v2)** for the independent
`arrhenius-lifetime-v2` analytical estimate:

```text
AF = exp(Ea/k * (1/Tref - 1/Top)) * voltage_stress^2 * current_stress^2
MTTF = base_hours / AF
R(t) = 100 exp(-t/MTTF)
```

Temperatures in this formula are kelvin; UI inputs are degrees C. Tests verify
the reference condition, shorter lifetime at higher temperature, squared
stress scaling, reliability shape and explicit rejection of invalid/numerically
unrepresentable assumptions. R multiplies by AF instead, producing the wrong
thermal direction; v2 deliberately does **not** claim R numerical parity.

These are generic, constant-hazard/squared-stress hypotheses, **not**
manufacturer-calibrated lifetime predictions or safety certification.
Base lifetime, activation energy, reference conditions and stress exponents
require device/failure-mechanism justification. Inputs are manual,
session-only and independent of lineup calculations/canvas properties.
No engineering-owner sign-off or device qualification is implied.

### Batch 22 - multiport Touchstone and converted-family export

[touchstone.py](src/rfview/domain/touchstone.py) now accepts Touchstone 1.x
`.s1p` through `.s9p` and Touchstone **2.0 full-matrix** `.ts`/`.sNp` files.
It supports declared port/frequency counts, positive real per-port references,
continued reference lines, both explicit two-port data orders, RI/MA/DB and
Hz/kHz/MHz/GHz. Two-port data uses its declared `21_12`/`12_21` order;
three or more ports use row-major ordering. Missing required counts/order,
inconsistent filename ports, duplicate declarations, content after End and
invalid/nonfinite references fail explicitly.

All supported ports have magnitude/phase views; diagonal S parameters have
Smith views using the corresponding port reference. Stability, circles,
conventional gain and parameter conversions remain **two-port** analyses.
Z/Y/h/ABCD require equal real port references; unequal references are preserved
in source S and rejected for these conversions, not silently renormalized.
Wave-transfer T remains dimensionless and preserves its source port references.

Source S download retains Touchstone 2.0 and per-port references where present.
Round-trip tests preserve source complex values exactly at 17-digit precision,
including asymmetric multiport matrices and alternate two-port ordering.
Original comments/formatting and dataset tags are not source-text round-tripped.
Limits remain 5 MiB / 100,000 parser frequencies / 2,000 viewer frequencies.
Mixed-mode, noise, information blocks, triangular matrices, complex or
frequency-varying references and vendor-specific comment normalization are
**not qualified**. Unsupported structural keywords are rejected, not ignored.
Files are not automatically transformed into a different wave normalization.

For a valid Z/Y/h/ABCD/T view, **Download converted family CSV** exports all four
matrix parameters at every frequency, not just the selected trace. Columns
identify frequency in GHz, representation, parameter, units, real/imaginary
values and both source port references. It uses the **same pure conversion
path** as the viewer, including mixed units for h/ABCD and frequency-specific
errors. A singular frequency rejects the entire export; no partial dataset
is presented. Converted CSV is not a standard Touchstone file or an import
format in this slice. Source S download remains independently available.

Qualification at batch 22: **807 passing Python tests**, strict source mypy,
Ruff, JavaScript syntax, dependency integrity and Pylance syntax checks.
Chromium exercises lifetime/gain version selection, actual multiport upload/
source round-trip and converted CSV download, load-pull upload/contours/
normalized export/sweeps/error recovery, and existing calculation/canvas/
workspace/session-isolation workflows. Responsive checks cover 375/768/1440 px.
This remains bounded qualification, not completion of workstreams 1-2.

### Batch 23 - advanced Touchstone structures

The parser now accepts Touchstone 2.0 **Lower/Upper** matrices, expanding
symmetric entries without complex conjugation. Source export emits equivalent
full matrices. Complex-valued independent tests cover 1/2/3/4/9 ports and both
triangular orientations. Version 1.x exports of three or more ports now wrap
matrix rows/pairs instead of producing overlong full-record lines.

**Mixed-Mode Order** is validated for descriptor count, complete port coverage,
non-overlapping matched D/C pairs and equal single-ended reference impedances
within each pair. The uploaded matrix remains in its **declared mode order**;
no differential-to-single-ended transformation is inferred. Sij selectors
refer to matrix mode indices, with the descriptor mapping displayed. Smith
plots use effective modal references: 2R differential, R/2 common, R
single-ended. Source exports preserve descriptors and the original
single-ended Reference values. Single-ended conversions, gain and stability
analysis are explicitly gated off for mixed-mode datasets, including two-mode
datasets; these views must not mislabel differential/common modes as two
physical single-ended ports.

Explicit **Touchstone 2.0 noise sections** are parsed independently of the
network frequency grid. The Noise view provides minimum-NF plots and a
unit-labelled numeric table. It preserves minimum NF in dB, optimum-source
Gamma magnitude/phase and **Rn in ohms**. The option-line impedance is retained
separately from per-port references: noise Gamma uses the option-line
reference, not the input port reference. Declared counts, five finite entries
per row, nonnegative Gamma magnitude/Rn, strictly increasing noise frequencies,
and the first-noise-frequency bound are enforced. Source download round-trips
noise and both reference conventions. No physical-limit repair, noise-circle
prediction or interpolation onto the network grid is performed.

These semantics follow the published
[IBIS Touchstone 2.0 specification](https://ibis.org/touchstone_ver2.0/touchstone_ver2_0.pdf),
especially Matrix Format, Mixed-Mode Order and Noise Parameter Data. Tolerant
whitespace around mixed-mode commas is accepted and canonicalized on export.
Noise follows the 100,000 parser / 2,000 UI frequency limits independently of
the network count. Version 1.x implicit noise tails, information blocks,
complex/frequency-varying references and mixed-mode basis conversion remain
unsupported rather than guessed.

### Batch 24 - simultaneous comparison and session slot lifecycle

**Compare four canvases** captures all four current lineups and calculates
them at the shared operating point. Cards simultaneously show simplified,
read-only topology diagrams, full/backoff output, net gain, DC, PAE/DE, model
warnings and calculation rationale. Empty or rejected slots are labelled
explicitly and never assigned invented numeric results. The active D3 editor
remains authoritative; card diagrams do not reproduce component geometry/
rotation/display styling. Diagrams are limited to 200 components per card,
with an explicit message above that limit; complete documents still calculate.
Editing, loading, slot changes or operating-point changes invalidate the
comparison rather than displaying stale results as current.

**Copy active canvas** uses the selected target slot. **Clear active canvas**
replaces the active slot with an empty document. Both require confirmation;
cancel leaves documents intact. Source/other slots retain their session
histories/zoom. Only the replaced slot restarts its history and zoom, as stated
in the confirmation. A target modified after the confirmation was requested
is rejected by a document comparison rather than overwritten. Same-slot
copies fail explicitly. Prepared workspace downloads/results/comparisons are
invalidated after replacement. Download the workspace first when an overwrite
must be recoverable. Alternatively, save a local project snapshot before replacement
(batch 32). Copy/clear itself does not create an automatic recovery point.

### Batch 25 - design controls and representative-file evidence

The toolbar now adds any of the six supported component types using the
retained D3 defaults: transistor, matching, splitter, combiner, offset line,
termination. Wiring remains the existing canvas protocol, not a new graph
engine or implicit topology synthesizer.

**Design metadata and geometry** exposes a separate selected-component form:
label, type-specific descriptive technology/bias/device/group/topology/
impedance/offset-role metadata, canvas X/Y, rotation and horizontal/vertical
flips. Both form IDs guard against stale selection. Geometry is finite and
bounded; metadata requires bounded text without control characters, and
offset roles must be phase/inverter. Unknown imported properties are retained.
These labels do not instantiate foundry models or synthesize matching
networks. Geometry/metadata changes use the existing custom-message,
snapshot/history path and preserve saved dual operating points; only relevant
transistor calculation-input edits invalidate those derived fields.

Both existing repository LPCWAVE samples are now part of automated acceptance:
**865 and 869 measurements**, every row's Pin/Pout/gain checked against source
columns, frequency retained and harmonic wave columns preserved as extras.
No source samples are copied or modified. This does not establish wave
normalization/calibration or harmonic engineering-model validity. CI watches
the sample directory so changes trigger the acceptance checks.

### Batch 26 - streamed ALPS MDF with explicit selection semantics

ALPS typed MDF is now a separate bounded adapter (`alps_mdf`) with explicit,
non-heuristic mappings and stream parsing:

- Streamed validation up to **64 MiB** per file (1 MiB max line), with no
  whole-file `read_text()` path.
- Full-file structural/numeric validation remains strict while importing only
  the selected subset for the viewer/export.
- Explicit Gamma reference-plane selection:
  - `dut`: `GLRE/GLIM`, `GSRE/GSIM`
  - `instrument`: `gamma_ld1_re/im`, `gamma_src1_re/im`
- Fixed measurement profile (Pin/Pout/Gt/Freq/Eff_col/Vout/Iout), while
  preserving compression and alternate columns in `point.extra` and quoted
  source strings in `point.source_strings`.
- Two explicit subset modes:
  - one selected Sweep block; or
  - fixed backoff (`BO`) across blocks, matched at 1e-8 dB tolerance.
- No silent truncation: selected subset still enforces the 2,000-point viewer
  bound and rejects overflow explicitly.

Repository qualification now includes both large ALPS samples:

- `...1.750GHz.tdp.mdf`: **500 blocks, 117,000 validated rows**
- `...1.800GHz.tdp.mdf`: **456 blocks, 97,584 validated rows**

For selected subsets, every row in the selected import was asserted against
the corresponding source columns for Pin/Pout/Gt/Gamma/Freq/Vout/Iout/Pdc.
ALPS backoff overlays now render as explicit same-frequency/fixed-BO
comparisons (not mislabeled fixed-Pin sweeps).

At batch 26, remaining RF-data blockers were narrowed to:

- Repository SPL preamble/efficiency-column dialect acceptance.
- Repository CST pre-block metadata acceptance and explicit wave-normalization
  qualification.
- Harmonic/wave-specific engineering workflows and broader overlay interaction.

### Batch 27 - repository SPL power-sweep-plan acceptance

Select **SPL_PLAN** for the repository's fundamental-only power-sweep-plan
dialect; **SPL** retains its generic-table semantics and efficiency unit
options. The new profile validates the preamble, frequency table, declared
source/load harmonics, Cartesian Gamma columns and every planned slot across
all sections. Truncation, slot-count mismatches, malformed or nonfinite
measurements and unsupported harmonics fail explicitly, including errors in
unselected sections.

Import once to discover the frequency catalogue, select a section, then
reimport. Only its valid measurements enter the viewer and normalized JSON;
other sections are not silently decimated. Limits are **5 MiB**, **100,000
source slots**, **1,000 sections** and **2,000 selected valid points**.
`VALID=0` slots are explicitly counted and excluded, not replaced with zero
power measurements. Valid rows retain original slot/section indices.
Rejected imports retain the last valid dataset.

The mapping uses `Pin_avail_dBm`, `Pout_dBm`, `Gt_dB`, `Freq`, `Vout_v`,
`Iout_mA` and `Eff_col` (drain efficiency in percent). PDC is
`Vout_v * Iout_mA / 1000`; PAE is derived from that DC power and Pin/Pout.
All original numeric columns remain in `extra["source.*"]`. In particular,
`Eff_%`, `Pdis`, `PoutW`, quiescent current and gate bias are not conflated
with drain efficiency, DC input, dBm-derived output watts or measured drain
current. Fractional-efficiency selection is rejected for this fixed-percent
profile, not silently ignored.

Repository acceptance covers **8 sections, 7,791 planned slots, 5,431 valid
measurements and 2,360 invalid slots**. Every valid row across all sections
is checked against source Gamma, Pin/Pout/gain, frequency, voltage/current,
efficiency and alternate columns. Browser acceptance checks actual upload,
section switching, normalized download, responsive controls and retention
after truncated-file/unit-option errors.

This is file/profile acceptance, not calibration or universal SPL support.
Gamma retains the source file's reference plane without transformation.
Exact measured Pin/source-Gamma/bias grouping stays unchanged: rounding or
nearest-neighbour selection must not fabricate constant-Pin contour sweeps.
Repository CST pre-block metadata, harmonic/wave workflows and advanced
RF-data interactions remain separate migration work.

### Batch 28 - CST block metadata and explicit wave interpretations

CST accepts both pre-`#BEGIN` and in-block metadata. Each block has isolated
Gamma/frequency/reference state; metadata cannot change after measurement
rows start. Missing load Gamma, empty/nested/unclosed blocks, duplicate
descriptors and mismatched/harmonic frequencies fail explicitly. Missing Z0
retains the legacy 50-ohm default only with a visible warning. Harmonic-count
declarations other than zero remain rejected pending dialect qualification.

The CST controls explicitly select peak-voltage, RMS-voltage or power-normalized
waves. Net powers use each port's own reference:

- Peak voltage: `(abs(a)^2 - abs(b)^2) / (2 * Z0)`.
- RMS voltage: `(abs(a)^2 - abs(b)^2) / Z0`.
- Power-normalized (sqrt W): `abs(a)^2 - abs(b)^2`.

Output uses outgoing `b2` minus incident `a2`; input uses `a1` minus `b1`.
These are user-selected interpretations, not instrument calibration claims.
Negative net power is retained, with undefined logarithms labelled rather
than clipped. Raw complex waves, DC measurements, frequency, block index
and reference impedances are included in normalized JSON.

Import once to discover blocks, choose a block and reimport. All source rows
are validated; only the selected block is displayed/exported within the
existing viewer cap. The block view includes net Pin/Pout versus source-row
index and a scrollable raw-wave/DC/reference table, independent of exact
Gamma/Pin/bias sweep grouping.

Repository acceptance verifies **365 blocks and all 8,915 measurements**
against direct source-wave power equations. This does not establish that the
chosen convention matches the measurement instrument; operator confirmation
and calibration evidence remain necessary.

### Batch 29 - implicit Touchstone 1.x noise tails

Two-port 1.x files now support implicit five-value noise tails following
complete network records. The first noise frequency must not exceed the
highest network frequency; subsequent noise frequencies are strictly increasing
on an independent grid. Noise Gamma remains magnitude/angle even when S data
uses RI or dB. Malformed tails fail rather than being dropped or interpreted
as complete network records.

Unlike version 2.0, version 1.x noise resistance is normalized to the option-line
reference impedance. Import converts it to ohms for the shared noise viewer.
For example, Rn=0.2 at R=75 ohm becomes 15 ohm. Export uses an explicit version
2.0 noise section with Rn in ohms, preserving numerical meaning rather than
source formatting. Tests cover wrapped network records, equal-frequency
boundaries, independent grids, invalid tails and v1-to-v2 round trips. Rules
follow the [IBIS Touchstone specification](https://ibis.org/touchstone_ver2.0/touchstone_ver2_0.pdf).

### Batch 30 - explicit mixed-mode basis transformations

The analysis-basis selector offers source, physical single-ended port order,
or an explicit mixed-mode order (for example, `D1,2 S3 C1,2`). Source data and
the source download remain unchanged. A separate transformed Touchstone 2.0
download exports the requested basis.

Transforms use orthonormal power-wave differential/common rows with paired
equal real single-ended references; effective differential/common impedances
are 2R and R/2. Physical port numbers, mode order, pair orientation and
unpaired single-ended ports are honored. No impedance renormalization is
inferred. Noise-parameter transformations are explicitly rejected.

Independent through-network checks, complex nonreciprocal round trips,
power-norm preservation, reversed/permuted mode orders and unequal-pair
rejection cover 2/3/4/9 ports. Two-port conversion/stability gates still apply
in mixed-mode basis; a successfully transformed single-ended dataset can use
the existing eligible single-ended analyses.

### Batch 31 - passive annotations and supported display controls

The selected-component **Component annotations and display** panel adds
matching bandwidth, splitter isolation/split ratio, combiner isolation/
load-modulation annotations and termination resistance/power-rating/VSWR.
Supported retained-renderer label/loss/topology/isolation/phase/display
toggles are exposed per component type. Fixed symbol values and
topology-specific renderer limitations are stated explicitly.

Edits are strictly validated, preserve unknown imported display fields and
use the existing snapshot/history protocol. Undo/redo applies to visual
properties; these edits do not clear transistor operating-point fields or
silently change the lineup model. Annotation values are not new unequal-split,
load-modulation or foundry synthesis models.

The browser protocol also explicitly decodes JSON at the input boundary:
Python Shiny freezes nested JSON arrays to tuples, which are not Pydantic
`JsonValue` lists. Restoring the JSON representation before schema validation
preserves component display arrays/workspace extras without weakening domain
validation or silently dropping fields.

Qualification through batch 31: **973 Python tests**, Ruff, strict source mypy,
dependency checks and Python compilation. Both Chromium suites
cover the established flows plus triangular/noise export, mixed-mode reference
labels/analysis gates, comparison freshness/responsiveness, component creation,
copy/clear confirmation/cancel/stale-target rejection, metadata/pose
undo/redo, streamed ALPS block/backoff selection and SPL plan frequency
selection with export/error retention. Batches 28-31 also pass integrated
Chromium checks for CST block/normalization changes and raw-wave tables,
v1 noise, transformed-versus-source downloads, invalid basis changes and
passive annotation undo/redo/rejected edits. A final focused rerun passed
116 tests after those browser additions. The advanced browser check waits
for server-rendered property forms after undo/redo, not just browser-local
component state. Pylance tools were unavailable during batch 27; runtime
tests, compilation and strict mypy provided local validation
instead. The legacy R sources remain unchanged. **Workstreams 1-2 are not
fully complete**: delivered slices do not imply full legacy-editor/file parity
or device-calibrated engineering acceptance.

### Batch 32 - local projects, immutable snapshots and restart recovery

The **Local projects** sidebar implements the approved single-workstation
SQLite target, not production authentication or a PostgreSQL substitute.
No database is opened or created at startup. Saving and listing are explicit.

- **Save as new project** creates a named project with revision 1. Names need not
  be unique; generated UUIDs identify projects. **Save new snapshot** appends an
  immutable revision of the attached project. Edits are never autosaved.
- Every snapshot includes all four documents, the active slot, and the shared
  input power, backoff, architecture and saved-browser-operating-point switch.
  Component IDs, connections, geometry, metadata and additional JSON fields
  retain their existing contracts. Snapshots have a 5 MiB total limit.
- **Open or recover local project** → **List local projects** lists the 100 most
  recently saved projects on page 1; the catalogue page control accesses older
  projects in additional pages of 100. Revision 0 opens the head; any positive existing
  revision opens that exact snapshot. History is not pruned. The picker is
  bounded without deleting or hiding older projects permanently.
- Recovery confirms replacement of all four canvases and operating-point
  controls. Changes made while the dialog is open, or a project updated by
  another session during confirmation, reject recovery without replacement.
  The project attaches only after the browser acknowledges restoration.
- Loading a historical snapshot does not move the database head backwards.
  A subsequent save appends a new revision; old payloads/timestamps remain
  unchanged. Saves compare the last observed head revision transactionally:
  stale sessions receive an explicit conflict rather than overwriting work.
- Transactions provide atomic writes; SHA-256 plus schema validation detect
  damaged payloads on read. Errors are logged/notified without pretending a
  save/recovery succeeded. A damaged revision does not prevent explicitly
  opening another intact revision. Checksums detect accidental damage; they
  are not signatures or protection against a user who can edit the database.
- Undo history, viewport zoom, selection, uploaded Touchstone/load-pull files,
  derived results and other calculator/advisory controls are **not** persisted.
  Recovery clears stale lineup calculations, comparison and prepared downloads;
  undo/zoom restart. Existing imported RF datasets are unchanged and are not
  claimed to belong to the recovered project. The legacy manual four-canvas
  JSON contract remains unchanged and does not capture shared controls.

Default Windows storage is `%LOCALAPPDATA%\RFView\projects.sqlite3`, outside the
checkout. If `LOCALAPPDATA` is unavailable, the fallback is
`~\.local\share\RFView\projects.sqlite3`. Override it with an absolute path:

```powershell
$env:RFVIEW_PROJECT_DB = 'D:\RFView-data\projects.sqlite3'
.\python_app\.venv\Scripts\python.exe -m shiny run --host 127.0.0.1 --port 3840 python_app\src\rfview\app.py
```

Keep the preview bound to loopback. All sessions use the same local catalogue;
there is **no authentication, role enforcement, tenant isolation or encryption**.
Use OS permissions and a private workstation directory appropriate for RF IP.
Do not expose this mode as a shared/network service. No RF uploads are persisted
automatically and no project content is sent to an external service.
Back up the database only with the app stopped or SQLite's online backup API;
do not copy a database mid-transaction. Database version mismatches and non-RFView
databases are rejected rather than adopted, reset or silently replaced.

Qualification: **1,011 passing Python tests** (38 new project-service tests),
Ruff, strict source mypy, compilation and dependency integrity checks.
The project service tests cover reconnect/reopen, full four-slot
round trips, immutable history, recovery append, concurrent writers,
transaction rollback, stale saves, corrupt payloads/schema versions, invalid
names/IDs/revisions, size bounds and explicit filesystem failures. A separate
Chromium check covers explicit saves, conflicts and stale recovery confirmation.
After stopping and restarting the actual server against the same isolated
database, it restores the head and historical snapshots and appends a recovery
revision. The existing baseline and advanced Chromium suites also pass.
Production identity/RBAC, PostgreSQL deployment, automatic crash-state capture
and simultaneous editable layouts are not delivered by this slice.

### Batch 33 - local read-only device knowledge-base search

The **Local device knowledge base** panel now searches the checked-in JSON under
`PA design App/data/kb/`. This is a local catalogue reader, not an AI agent,
recommendation engine, Chroma integration or crawler. Searches do not access the
network, include project state, persist queries, or modify vendor records.

- Case-insensitive text search covers the complete validated record, including
  part number, manufacturer, notes, application, tags and retained vendor fields.
- Manufacturer and technology filters require exact matches after case-folding.
  Optional frequency filtering requires the requested MHz value to be within
  the record's inclusive `[freq_min_mhz, freq_max_mhz]` band. Active/EOL status
  is shown, not silently used as a filter.
- Search results are deterministic, capped at 50 cards by the app (200 in the
  reusable query API). The status reports the total and asks for narrower filters
  when results are truncated. Select a device to inspect its stored fields,
  relative vendor-file location and SHA-256 of the complete source file.
- The reader rejects invalid UTF-8/JSON, duplicate JSON keys or device IDs,
  non-finite numbers (including JSON exponent overflow), missing required fields,
  reversed bands, invalid core
  power/efficiency ranges, symlinks, files over 8 MiB, a KB over 32 MiB and
  catalogs over 10,000 records. A bad source rejects the search rather than
  returning a partial catalogue.
- Source/confidence/provenance fields are presented as recorded. In particular,
  `from_training` and pilot/auto-seeded records are **not** promoted to datasheet
  facts, approval, or design recommendations by this view. Device-specific
  validation and human engineering review remain required.

Qualification: focused tests load all **22 actual records across four vendors**,
verify file hashes and retained vendor extras, exercise text and exact filters,
MHz boundaries, sorting/truncation, malformed and hostile JSON, data bounds,
duplicate IDs and source symlinks. The advanced Chromium suite exercises the
full-catalog and NXP/frequency/part-number searches at 375/768/1440 px.
At the end of batch 33 the full Python suite passed **1,048 tests**, with one
platform skip because directory symlink creation is not permitted on this
Windows account; Ruff, strict source mypy, compilation and dependency checks
pass.
This slice intentionally makes no claim that the LLM agents, embeddings/vector
database, AI prompts, guarded Python ingestion/application workflow, or
human-reviewed datasheet extraction have migrated.

### Batch 34 - attach a catalog citation to a transistor

The new **Attach / replace selected transistor reference** action connects the
local device catalog to canvas and explicitly saved project work without
conflating a literature record with an RF device model.

- Search for and select a local catalog record, then select a transistor on the
  active canvas and explicitly attach it. A non-transistor selection or a
  catalog item outside the current search results is rejected.
- The component stores a version-independent JSON reference under
  `properties.kb_device_reference`: identity/vendor/technology, rated frequency
  band, recorded source/confidence/status, optional HTTPS datasheet URL, source
  file path and catalog-file SHA-256. Unknown properties, units and source
  records are not copied wholesale into the design.
- The canvas property panel displays it separately as provenance. The ordinary
  component undo/redo history governs attachment changes. Existing references
  are replaced only by the explicit attach/replace action.
- The attachment does not set, infer or change gain, efficiency, output power,
  supply, Ropt, load-pull contours, technology model, guardrail assumptions or
  any other calculation field. It is a citation link, not a validated or
  calibrated transistor model.
- Explicit local-project snapshots retain the reference with its transistor.
  The test reopens the saved snapshot, validates the retained record, and
  checks that the pre-existing calculation property remains unchanged.

Qualification: the advanced browser suite selects an NXP catalog entry and a
transistor, checks its provenance panel, verifies the gain property is
unchanged, and exercises undo/redo. Unit tests reject unsafe URLs and escaping
source paths and verify project snapshot durability. Both baseline and advanced
Chromium suites pass at their established viewport checks. The full Python
suite passes **1,055 tests** (one Windows permission skip); Ruff, strict source
mypy, compilation, dependency and diff checks pass.

### Batch 35 - bounded RF CAD document contract

Adds a Python-side import/export contract for the standalone legacy RF-CAD JSON
shape, without claiming renderer or engineering-workflow parity.

- Accepts the versioned v1.0 document and legacy bare component arrays;
  bare arrays normalize to a v1.0 document on export.
- Validates supported legacy component types, their required positive geometry
  values, positions, substrate fields, identifiers, duplicate IDs and bounded
  document/component sizes. Duplicate JSON keys, non-finite values, invalid
  UTF-8 and unsupported versions are rejected.
- Preserves unrecognized document, substrate, component and parameter fields.
  The palette's `ms` spelling is retained as-is; renderer compatibility for
  that alias is not implied.
- File access is isolated in the service layer. The domain model remains free
  of filesystem, UI, database and network dependencies.

Qualification: the focused CAD and domain-contract tests pass, and the full
Python suite passes **1,095 tests** with one Windows permission skip. Ruff and
strict source mypy pass. Layout editing, DRC, routing, substrate synthesis, EM
analysis and standalone/integrated workflow parity remain unimplemented.

### Batch 36 - standalone RF-CAD JSON import/export panel

Adds an isolated RF-CAD interchange panel to the Python app. Users can upload a
supported CAD JSON file, inspect its format version, component count, substrate
summary and per-type counts, then download normalized JSON. Unknown fields
remain in the exported document, and a rejected subsequent upload leaves the
last valid imported document available for download. The operation is session-only.

CAD documents remain separate from the PA lineup canvas and its workspace
snapshots. The panel does not offer editing, DRC, routing, substrate synthesis,
EM analysis or integrated/standalone workflow parity. Those require separate
implementation and engineering qualification.

Qualification: the Chromium smoke flow uploads and downloads a legacy-shaped
document, checks substrate/component summaries and unknown-field retention, and
verifies failed imports preserve the last valid export. The standalone CAD
contract tests remain covered by the full Python suite.

### Batch 37 - bounded standalone CAD position overview

The imported CAD panel now provides a read-only SVG overview using component
origin coordinates in millimetres, with IDs and coordinates available on each
marker. The preview renders at most 250 markers; for larger documents, the UI
states the limit while normalized JSON export retains every component. The
source document and coordinates are not modified.

This is a position overview only: the legacy CAD footprint renderer is not
ported. Marker size does not represent physical dimensions; layer stacking,
connectivity, bend/coupler geometry, clearances, DRC and EM are not shown or
evaluated. It is not suitable for fabrication or engineering sign-off.

Qualification: Chromium verifies coordinate information in SVG marker titles,
the 250-marker preview cap and that all 251 components remain in the download.
Responsive width checks and invalid-upload retention also pass.

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
.\python_app\.venv\Scripts\python.exe python_app\tests\browser_advanced_smoke.py http://127.0.0.1:3840
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

Steps 1-2 are **not signed off as complete** by batches 28-31. The remaining
software gates and external acceptance gates are distinct:

| Gate | Status |
| --- | --- |
| Repository CST, SPL, ALPS and LPCWAVE numerical import checks | Delivered within the documented dialects/bounds |
| Touchstone 1.x/2.0 noise and explicit mixed-mode transforms | Delivered within documented real-reference/basis limits |
| Passive annotation/display edit history | Delivered for fields supported by the retained renderer |
| Harmonic-specific vendor parsing/analysis and richer RF-data interactions | Remaining implementation/qualification |
| Simultaneous editable multi-canvas layouts | Remaining implementation; comparison cards are read-only |
| Local persistent workspace save/recovery beyond manual JSON | Delivered by batch 32; explicit snapshots, four slots and operating-point controls |
| Production multi-user persistence, identity and RBAC | Remaining; local SQLite mode is unauthenticated and single-user only |
| Remaining synthesis/editor controls and interaction parity | Remaining implementation/acceptance |
| Device-calibrated model accuracy and wave-convention/calibration sign-off | External engineering evidence and RF-owner acceptance required |
| Local checked-in device catalog search | Delivered by batch 33; read-only, filters and source digests |
| Explicit KB citation attachment to a canvas/project | Delivered by batch 34; provenance-only, never populates the physics model |
| Strict RF-CAD JSON contract, import/export and position overview | Delivered by batches 35-37; separate interchange panel, not CAD editing |
| AI agents, vector retrieval and guarded Python ingestion workflow | Remaining; no LLM, Chroma or KB write/apply path is claimed |

1. Complete remaining RF-data acceptance: harmonic-specific vendor workflows,
   calibration/wave-convention qualification and richer overlays/interaction.
   The repository CST dialect, implicit 1.x/explicit 2.0 noise, mixed-mode
   transforms, triangular matrices, streamed ALPS MDF and SPL plan selection
   are delivered, not universal vendor or calibration parity.
2. Complete remaining calculations, engineering-model decisions, legacy
   synthesis/editor controls, simultaneous editable comparison and
   production multi-canvas lifecycle; qualify advanced chart interactions and
   device-calibrated model assumptions separately. Four session slots,
   read-only simultaneous comparison, confirmed copy/clear, calculation/pose/
   metadata/annotation/display controls and corrected generic gain/lifetime options are delivered,
   not full parity.
3. Extend local project persistence/snapshots/recovery to production PostgreSQL,
   authenticated identity, role-based access and additional project datasets.
4. Port the AI agent runtime/individual agents, Chroma retrieval and guarded
   Python KB ingestion/review/apply workflow; retain provenance and human
   approval gates. The local catalogue browser in batch 33 is not this work.
5. Complete and qualify integrated and standalone RF CAD separately.
6. Convert education/manual/IFX documents and Web Page Knitter to Python-executed
   builds, retaining their interactive assets.
7. Package deployment; measure performance/capacity; qualify data conversion and
   rollback; conduct whole-workspace user acceptance.

Only archive R after the final acceptance gates pass. Numeric reproducibility
does not establish visual, workflow, file, AI or performance parity.
See the [workspace migration assessment](../PYTHON_MIGRATION_REVIEW.html) for the
broader scope, effort estimate and retirement gates.
