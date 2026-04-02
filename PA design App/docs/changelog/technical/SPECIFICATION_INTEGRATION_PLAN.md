# Specification Integration Plan - PA Design App
**Date**: March 4, 2026  
**Objective**: Wire Specifications to Global Parameters and Individual Components with backward/forward cascade calculations

---

## 1. ARCHITECTURAL OVERVIEW

### Current State
```
[Specifications Tab]  (Isolated - no connections)
       ↓ (NO LINK)
[Global Lineup Parameters]  (Standalone)
       ↓ (Manual only)
[Individual Components]  (Direct user input)
```

### Target State
```
[Specifications Tab]
       ↓ (Primary Specs: P3dB, Freq, Gain)
       ↓
[Global Lineup Parameters]
       ↓ (Cascade calculations)
       ↓
[Individual Components]
       ↓ (Auto-adapt parameters)
       ↓
[Validation & Verification]
```

---

## 2. PRIMARY SPECIFICATIONS (Driving Parameters)

### 2.1 Three Primary Specs
1. **P3dB (Power)** - Target output power at 3dB compression
   - Units: dBm
   - Example: 55.3 dBm
   - **Role**: Determines component power handling requirements

2. **Frequency (Freq)** - Operating frequency
   - Units: GHz (will need conversion from MHz in specs tab)
   - Range: Low, Mid, High frequency bands
   - Example: 1.805 GHz (converted from 1805 MHz)
   - **Role**: Affects matching networks, efficiency curves, technology selection

3. **Gain (Gain)** - Total lineup gain
   - Units: dB
   - Example: 41.5 dB
   - **Role**: Determines number of stages, gain distribution

### 2.2 Secondary Specs (Constraints)
- Supply Voltage → Component Vdd
- Efficiency Target → Bias class selection
- AM-PM, Group Delay → Technology/topology constraints
- ACP, Gain Ripple → Linearity requirements

---

## 3. CALCULATION CASCADE METHODOLOGY

### 3.1 Forward Cascade (Spec → Component)

#### Stage 1: Specifications → Global Parameters
```javascript
// User enters in Specifications tab:
spec_p3db = 55.3 dBm
spec_frequency = 1805 MHz → 1.805 GHz
spec_gain = 41.5 dB

// Auto-populate Global Lineup Parameters:
global_frequency = spec_frequency / 1000  // Convert MHz to GHz
global_pout = spec_p3db  // Target output power
global_gain_target = spec_gain  // Total gain requirement
global_backoff = 6 dB  // User can adjust
```

#### Stage 2: Global Parameters → Component Distribution
```javascript
// Calculate required input power:
Pin_required = Pout - Total_Gain
Pin_required = 55.3 - 41.5 = 13.8 dBm

// Determine number of stages based on gain:
if (total_gain < 15) {
  stages = 1  // Single stage
} else if (total_gain < 30) {
  stages = 2  // Driver + PA
} else if (total_gain < 45) {
  stages = 3  // Pre-driver + Driver + PA
} else {
  stages = 4  // Multi-stage
}

// For 41.5 dB: 3 stages recommended
// Gain distribution: 15 dB (PreDriver) + 15 dB (Driver) + 11.5 dB (PA)
```

#### Stage 3: Component Parameter Calculation

**For each component:**
```javascript
// Transistor (PA stage):
{
  frequency: global_frequency,  // 1.805 GHz
  pout: global_pout,  // 55.3 dBm (final stage)
  gain: calculated_stage_gain,  // 11.5 dB (for PA)
  vdd: spec_supply_voltage,  // 30V
  efficiency_target: spec_efficiency,  // 47%
  
  // Back-calculate P1dB from P3dB:
  p1db: p3db - 2,  // Typically 2dB below P3dB
  
  // Select technology based on freq + power:
  technology: selectTechnology(frequency, pout, vdd),
  
  // Select bias class based on efficiency target:
  biasClass: selectBiasClass(efficiency_target, topology)
}

// Matching Networks:
{
  frequency: global_frequency,
  impedance_transform: calculateImpedance(pout, vdd),
  bandwidth: spec_bandwidth  // From specifications
}

// Splitter/Combiner:
{
  frequency: global_frequency,
  power_split_ratio: calculateRatio(topology),
  insertion_loss: estimateInsertionLoss(frequency, topology)
}
```

### 3.2 Backward Verification (Component → Spec)

After auto-population, verify that component chain meets specs:
```javascript
function verifyLineup() {
  // 1. Sum gains through chain
  let total_gain = 0;
  components.filter(c => c.type === 'transistor').forEach(t => {
    total_gain += t.properties.gain;
  });
  
  // 2. Check against target
  if (Math.abs(total_gain - spec_gain) > 0.5) {
    warning("Total gain mismatch: " + total_gain + " vs " + spec_gain);
    suggest_adjustment();
  }
  
  // 3. Verify power capability
  let final_stage = getOutputStage();
  if (final_stage.pout < spec_p3db) {
    error("Output stage insufficient: " + final_stage.pout + " < " + spec_p3db);
  }
  
  // 4. Check frequency range
  components.forEach(c => {
    if (c.frequency !== global_frequency) {
      warning("Frequency mismatch in component: " + c.id);
    }
  });
}
```

---

## 4. TEMPLATE UPDATES

### 4.1 Template Recalculation Strategy

Each preset template needs parameters adjusted based on specs:

**Example: Conventional Doherty Template**
```javascript
// CURRENT (Hardcoded):
{
  driver: { pout: 35, gain: 15, tech: "GaN" },
  main_pa: { pout: 43, gain: 12, tech: "GaN" },
  aux_pa: { pout: 43, gain: 12, tech: "GaN" }
}

// NEW (Spec-driven):
function generateConventionalDoherty(specs) {
  let total_components = 3;  // Driver + Main + Aux
  
  // Calculate power distribution
  let driver_pout = specs.p3db - 10;  // 10dB below output
  let main_pout = specs.p3db;
  let aux_pout = specs.p3db;  // Same as main for balanced
  
  // Calculate gain distribution
  let gain_per_stage = specs.gain / 2;  // Driver + PA stages
  let driver_gain = Math.min(18, gain_per_stage);  // Cap at 18dB
  let pa_gain = specs.gain - driver_gain;
  
  return {
    driver: {
      pout: driver_pout,
      gain: driver_gain,
      freq: specs.frequency,
      tech: selectTech(specs.frequency, driver_pout),
      vdd: specs.supply_voltage
    },
    main_pa: {
      pout: main_pout,
      gain: pa_gain,
      freq: specs.frequency,
      tech: selectTech(specs.frequency, main_pout),
      biasClass: "AB",
      vdd: specs.supply_voltage
    },
    aux_pa: {
      pout: aux_pout,
      gain: pa_gain,
      freq: specs.frequency,
      tech: selectTech(specs.frequency, aux_pout),
      biasClass: "C",
      vdd: specs.supply_voltage
    }
  };
}
```

### 4.2 Technology Selection Logic

```javascript
function selectTechnology(freq_ghz, pout_dbm, vdd) {
  // Convert power to watts for easier logic
  let pout_watts = Math.pow(10, (pout_dbm - 30) / 10);
  
  // Decision matrix
  if (freq_ghz < 1) {
    // HF/VHF
    if (pout_watts > 100) return "LDMOS";
    else return "Si";
  } else if (freq_ghz < 3) {
    // Sub-3GHz (LTE, etc.)
    if (pout_watts > 50) return "GaN";
    else if (pout_watts > 10) return "LDMOS";
    else return "GaAs";
  } else if (freq_ghz < 6) {
    // Mid-band (5G)
    if (pout_watts > 20) return "GaN";
    else return "GaAs";
  } else {
    // mmWave
    if (pout_watts > 5) return "GaN";
    else return "GaAs";
  }
}

function selectBiasClass(efficiency_target, topology) {
  if (topology === "doherty") {
    return { main: "AB", aux: "C" };
  } else if (efficiency_target > 50) {
    return "B";  // Class B for high efficiency
  } else if (efficiency_target > 40) {
    return "AB";  // Class AB balanced
  } else {
    return "A";  // Class A for linearity
  }
}
```

---

## 5. IMPLEMENTATION PLAN

### Phase 1: Data Binding Infrastructure
**Objective**: Connect Specifications to Global Parameters

**Tasks**:
1. Create reactive observers in R for spec changes
2. Auto-update `global_frequency` when `spec_frequency` changes
3. Add conversion logic (MHz → GHz)
4. Add "Apply Specs to Lineup" button
5. Create JavaScript message handler for spec updates

**Files to Modify**:
- `R/app.R`: Add observers for spec inputs
- `www/js/pa_lineup_canvas.js`: Add spec update handlers

**Deliverable**: Changing specs auto-updates global parameters

---

### Phase 2: Component Auto-Population
**Objective**: Generate component parameters from specs

**Tasks**:
1. Create gain distribution algorithm
2. Create power distribution algorithm  
3. Add technology selection logic
4. Create `applySpecsToComponents()` function
5. Add validation warnings

**Files to Modify**:
- `www/js/pa_lineup_canvas.js`: Add auto-population logic
- `R/app.R`: Add R-side validation

**Deliverable**: Button-triggered component parameter generation

---

### Phase 3: Template Recalculation
**Objective**: Update all preset templates to be spec-aware

**Tasks**:
1. Refactor each preset function to accept specs parameter
2. Add parameter calculation logic to each template
3. Update template loading to apply current specs
4. Add "Regenerate from Specs" button for templates

**Files to Modify**:
- `www/js/pa_lineup_canvas.js`: Refactor all `loadPreset_*()` functions

**Deliverable**: Templates adapt to current specifications

---

### Phase 4: Validation & Verification
**Objective**: Ensure lineup meets specifications

**Tasks**:
1. Create `validateLineup()` function
2. Check total gain vs spec_gain
3. Check output power vs spec_p3db
4. Check frequency consistency
5. Add visual indicators (✓ / ⚠ / ✗)

**Files to Modify**:
- `www/js/pa_lineup_canvas.js`: Add validation logic
- `R/app.R`: Add server-side verification
- `www/custom.css`: Add validation styling

**Deliverable**: Real-time lineup validation against specs

---

## 6. TESTING STRATEGY

### 6.1 Unit Tests

**Test 1: Spec-to-Global Binding**
```
Input:  spec_frequency = 2600 MHz
        spec_p3db = 50 dBm
        spec_gain = 30 dB

Action: Change spec_frequency to 1800 MHz

Expected:
  - global_frequency updates to 1.8 GHz
  - Components refresh with new frequency
  - No errors in console
```

**Test 2: Gain Distribution**
```
Input:  spec_gain = 40 dB

Expected Stages:
  - 3 stages: PreDriver (15dB) + Driver (15dB) + PA (10dB)
  - Total gain = 40 dB ± 0.5 dB
  - Each component has correct gain value
```

**Test 3: Power Cascade**
```
Input:  spec_p3db = 55 dBm
        spec_gain = 40 dB

Expected:
  - Pin = 55 - 40 = 15 dBm (input to lineup)
  - Driver Pout = ~25 dBm (intermediate)
  - PA Pout = 55 dBm (final)
  - P1dB values correct (P3dB - 2)
```

**Test 4: Technology Selection**
```
Input:  freq = 1.8 GHz, Pout = 50 dBm → Expect: GaN
Input:  freq = 1.8 GHz, Pout = 35 dBm → Expect: LDMOS
Input:  freq = 5.8 GHz, Pout = 40 dBm → Expect: GaN
Input:  freq = 28 GHz, Pout = 30 dBm → Expect: GaAs
```

### 6.2 Integration Tests

**Test 5: Template Adaptation**
```
Steps:
1. Set specs: P3dB=50dBm, Freq=2.6GHz, Gain=35dB
2. Load "Conventional Doherty" template
3. Verify all components match specs
4. Change specs: P3dB=60dBm
5. Click "Regenerate from Specs"
6. Verify components updated to new power level
```

**Test 6: User Override**
```
Steps:
1. Apply specs to lineup
2. Manually change one component (e.g., Driver gain 15→18 dB)
3. Verify validation shows warning (total gain mismatch)
4. Verify visual indicator appears
5. Click "Revert to Spec" → component returns to calculated value
```

**Test 7: Multi-Frequency Sweep**
```
Test frequencies: 0.9, 1.8, 2.6, 3.5, 5.8, 28 GHz
For each:
  - Apply to specs
  - Load template
  - Verify technology selection appropriate
  - Verify efficiency estimates realistic
  - No JavaScript errors
```

### 6.3 Validation Tests

**Test 8: Gain Validation**
```
Create lineup: Driver (15dB) + PA (20dB)
Spec requires: 40 dB total

Expected Validation:
  ⚠ Warning: "Total gain (35 dB) below target (40 dB)"
  Suggestion: "Add pre-driver stage or increase gains"
```

**Test 9: Power Validation**
```
Create lineup: PA with Pout=48dBm
Spec requires: P3dB = 55 dBm

Expected Validation:
  ✗ Error: "Output power insufficient (48 < 55 dBm)"
  Suggestion: "Increase PA size or add power combining"
```

**Test 10: Frequency Consistency**
```
Set global freq: 2.6 GHz
Manually change one component to 1.8 GHz

Expected Validation:
  ⚠ Warning: "Frequency mismatch in component #3"
  Action: Highlight component in red
```

---

## 7. DATA STRUCTURES

### 7.1 Specifications Object
```javascript
window.lineupSpecs = {
  // Primary (driving)
  p3db: 55.3,           // dBm
  frequency: 1.805,      // GHz (converted from MHz)
  gain: 41.5,           // dB
  
  // Secondary (constraints)
  supply_voltage: 30,    // V
  efficiency_target: 47, // %
  am_pm_p3db: -25,      // deg
  am_pm_dispersion: 8,   // deg
  group_delay: 1,        // ns
  acp: -30,             // dBc
  gain_ripple_inband: 1.0,   // dB
  gain_ripple_3xband: 3.0,   // dB
  input_return_loss: -15,     // dB
  vbw: 225,             // MHz
  test_conditions: "cw"
};
```

### 7.2 Component Parameters (Extended)
```javascript
component = {
  id: 1,
  type: "transistor",
  x: 300, y: 300,
  properties: {
    label: "Main PA",
    
    // Core parameters
    frequency: 1.805,  // GHz (from specs)
    pout: 55.3,       // dBm (from specs cascade)
    p1db: 53.3,       // dBm (calculated)
    p3db: 55.3,       // dBm (spec target)
    gain: 12,         // dB (distributed)
    
    // Derived from specs
    technology: "GaN",     // Auto-selected
    biasClass: "AB",       // Auto-selected
    vdd: 30,              // From spec_supply_voltage
    
    // Performance
    pae: 55,          // % (estimated from bias class)
    rth: 2.5,         // °C/W
    
    // Source tracking
    spec_driven: true,      // Flag: generated from specs
    manually_modified: false // Flag: user override
  }
};
```

### 7.3 Validation State
```javascript
window.lineupValidation = {
  valid: false,
  errors: [
    { type: "error", component_id: 5, message: "Output power insufficient" }
  ],
  warnings: [
    { type: "warning", component_id: 3, message: "Frequency mismatch" }
  ],
  suggestions: [
    "Add pre-driver stage for adequate gain"
  ],
  metrics: {
    total_gain: 38.5,       // Calculated
    target_gain: 41.5,      // From spec
    gain_delta: -3.0,       // Shortfall
    
    total_pout: 53.2,       // Calculated
    target_pout: 55.3,      // From spec
    power_delta: -2.1       // Shortfall
  }
};
```

---

## 8. USER INTERFACE ENHANCEMENTS

### 8.1 Specifications Tab Updates

**Add Buttons**:
```html
<actionButton id="apply_specs_to_lineup" 
  class="btn-primary btn-block"
  icon="arrow-down">
  Apply Specs to Lineup ↓
</actionButton>

<actionButton id="refresh_from_lineup"
  class="btn-secondary btn-block" 
  icon="arrow-up">
  Refresh from Lineup ↑
</actionButton>
```

**Visual Indicators**:
- ✓ Green checkmark when component matches spec
- ⚠ Yellow warning when component deviates
- ✗ Red X when critical mismatch

### 8.2 Component Property Editor Updates

**Add "Spec Source" Indicator**:
```html
<div class="spec-source-badge">
  <span v-if="spec_driven">✓ From Specifications</span>
  <span v-if="manually_modified">✏ User Modified</span>
  <button onclick="revertToSpec()">Revert to Spec</button>
</div>
```

### 8.3 Validation Panel (New)

Add below calculation results:
```html
<box title="Lineup Validation" status="info">
  <div id="validation_summary">
    <h5>Against Specifications:</h5>
    <table>
      <tr>
        <td>Total Gain:</td>
        <td id="val_gain">38.5 dB</td>
        <td class="spec-target">Target: 41.5 dB</td>
        <td><span class="badge badge-warning">-3.0 dB</span></td>
      </tr>
      <tr>
        <td>Output Power:</td>
        <td id="val_pout">55.1 dBm</td>
        <td class="spec-target">Target: 55.3 dBm</td>
        <td><span class="badge badge-success">✓</span></td>
      </tr>
      <tr>
        <td>Frequency:</td>
        <td id="val_freq">1.805 GHz</td>
        <td class="spec-target">Target: 1.805 GHz</td>
        <td><span class="badge badge-success">✓</span></td>
      </tr>
    </table>
    
    <div class="validation-actions">
      <button onclick="autoFix()">Auto-Fix Issues</button>
    </div>
  </div>
</box>
```

---

## 9. INTEGRITY GUARANTEES

### 9.1 Calculation Integrity

**Rule 1: Conservation of Power**
```
Pin + Sum(Gains) = Pout + Sum(Losses)
```
Verify at each step.

**Rule 2: Frequency Consistency**
```
All components must operate at same frequency ± tolerance
```
Flag mismatches immediately.

**Rule 3: Gain Additivity**
```
Total_Gain = Sum(Stage_Gains) - Sum(Insertion_Losses)
```
Calculate and validate continuously.

### 9.2 Architecture Integrity

**Constraint 1: Topology Rules**
```javascript
// Doherty: Main + Aux must have similar power
if (topology === "doherty") {
  assert(Math.abs(main.pout - aux.pout) < 3);  // Within 3dB
}

// Balanced: All branches equal
if (topology === "balanced") {
  let powers = branches.map(b => b.pout);
  assert(Math.max(...powers) - Math.min(...powers) < 1);
}
```

**Constraint 2: Component Order**
```javascript
// Power must increase left to right
for (let i = 1; i < components.length; i++) {
  if (components[i].type === "transistor") {
    assert(components[i].pout >= components[i-1].pout);
  }
}
```

### 9.3 Verification Strategy

**Level 1: Real-time Validation** (in UI)
- Instant feedback as user types
- Visual indicators (✓/⚠/✗)
- No lineup calculation allowed if critical errors

**Level 2: Pre-Calculation Check** (before calculate button)
- Verify all components have required parameters
- Check topology consistency
- Warn about sub-optimal configurations

**Level 3: Post-Calculation Verification** (after results)
- Compare calculated vs expected results
- Check physical plausibility (e.g., PAE < 85%)
- Highlight unexpected outcomes

---

## 10. ROLLOUT PLAN

### Step 1: Proof of Concept (1 template)
- Implement spec binding for Single Doherty only
- Test thoroughly
- Get user feedback
- Iterate if needed

### Step 2: Core Infrastructure
- Implement all Phase 1 & 2 tasks
- Focus on robust data flow
- Add comprehensive logging
- Deploy to test

### Step 3: Template Migration
- Update remaining 10 templates
- Test each individually
- Document parameter formulas

### Step 4: Validation System
- Implement all validation checks
- Add UI indicators
- Test edge cases

### Step 5: Production Release
- Full regression testing
- Update documentation
- User training
- Deploy to main

---

## 11. RISK MITIGATION

### Risk 1: Breaking Existing Workflows
**Mitigation**: 
- Add "Legacy Mode" toggle to bypass spec-driven calculations
- Preserve existing manual input capability
- Make spec-application opt-in initially

### Risk 2: Incorrect Calculations
**Mitigation**:
- Extensive unit tests for each formula
- Cross-check against known good designs
- Add "calculation audit log" to trace decisions
- Peer review of all formulas

### Risk 3: Template Inconsistencies
**Mitigation**:
- Standardize template generation functions
- Use shared utility functions for common calcs
- Version control for template definitions
- Regression test suite comparing old vs new

### Risk 4: Performance Degradation
**Mitigation**:
- Profile calculation performance
- Debounce spec updates (don't recalc on every keystroke)
- Use memoization for expensive calculations
- Background workers for heavy calculations

---

## 12. SUCCESS CRITERIA

✓ **Functional**:
- Specs correctly populate global parameters (100% accuracy)
- Component parameters calculated from specs (validated against hand calcs)
- All 11 templates adapt to specs
- Validation catches 95%+ of configuration errors

✓ **Performance**:
- Spec-to-component cascade < 200ms
- Template loading < 500ms
- Validation runs real-time (< 100ms)

✓ **Usability**:
- User can go from specs to validated lineup in < 1 minute
- Visual feedback is clear and actionable
- No JavaScript errors in console
- No disruption to existing manual workflows

✓ **Quality**:
- All unit tests pass (target: 50+ tests)
- Zero critical bugs in production
- Calculation accuracy ±1% vs theoretical
- User satisfaction rating > 4/5

---

## 13. NEXT STEPS

**Before Implementation**:
1. ✅ Review this plan with user
2. ⬜ Agree on calculation formulas
3. ⬜ Prioritize phases (all or subset?)
4. ⬜ Set timeline for each phase
5. ⬜ Identify any missing requirements

**Then Proceed**:
- Phase 1 implementation
- Iterative testing
- User feedback loop
- Continue to next phase

---

## APPENDIX A: Calculation Reference Formulas

### Power Calculations
```javascript
// Convert dBm to Watts
P_watts = 10 ^ ((P_dbm - 30) / 10)

// Convert Watts to dBm  
P_dbm = 10 * log10(P_watts) + 30

// P1dB estimation from P3dB
P1dB = P3dB - 2  // Typical for solid state

// PAE estimation
PAE = (Pout_watts - Pin_watts) / PDC_watts * 100
```

### Gain Calculations
```javascript
// Total gain
G_total = Sum(G_stage) - Sum(Loss_mismatch) - Sum(Loss_insertion)

// Required input power
Pin = Pout - G_total

// Stage gain distribution (heuristic)
if (stages == 1) {
  G1 = G_total;
} else if (stages == 2) {
  G1 = min(18, G_total/2);  // Driver
  G2 = G_total - G1;        // PA
} else if (stages == 3) {
  G1 = 15;  // Pre-driver
  G2 = 15;  // Driver
  G3 = G_total - G1 - G2;  // PA
}
```

### Impedance Calculations
```javascript
// Optimal load impedance for given Pout and Vdd
Ropt = (Vdd - Vknee)^2 / (2 * Pout_watts)

// For GaN: Vknee ≈ 3V
// For LDMOS: Vknee ≈ 5V
// For GaAs: Vknee ≈ 2V
```

---

**END OF PLAN**
