# Specification-Driven Design - Proof of Concept
**Date**: March 4, 2026  
**Status**: ✅ **PHASE 1 & 2 COMPLETE**  
**Scope**: Single Doherty Template (POC)

---

## 🎯 What's Been Implemented

### **Phase 1: Spec-to-Global Binding** ✅
Specifications now automatically update Global Lineup Parameters with proper unit conversions.

### **Phase 2: Component Auto-Population** ✅
Existing template components adapt to specifications using intelligent algorithms for:
- Technology selection based on fT/fmax requirements
- Gain distribution across stages
- Power cascade calculations
- Passive component loss estimation
- Bias class selection for efficiency targets

---

## 📋 New Features

### 1. **Specification Tab Enhancements**

Two new buttons added to the Specifications box:

#### **"Apply Specs to Lineup ↓"** (Primary Button - Blue)
- Adapts ALL components in current template to meet specifications
- Updates:
  - ✓ Transistor technology (GaN/LDMOS/GaAs based on freq + power)
  - ✓ Component frequencies (MHz → GHz conversion)
  - ✓ Gain distribution across stages
  - ✓ Power levels (P3dB, P1dB, Pout)
  - ✓ Bias classes (Class A/AB/C based on topology)
  - ✓ PAE estimates (based on bias class + frequency)
  - ✓ Passive losses (frequency-dependent curves)
  - ✓ Supply voltage (Vdd)

#### **"Update Global Params ↓"** (Secondary Button - Info)
- Only updates Global Lineup Parameters
- Quick frequency conversion (MHz → GHz)
- Does NOT modify component properties

---

## 🔧 Technology Selection Logic

### **Implemented Algorithm**

Based on **Frequency Planning** tab data (fT/fmax requirements):

```
Rule: fT > 5 × operating_frequency
```

#### **Decision Matrix**

| Frequency Range | Power Condition | Technology | fT Range | Rationale |
|----------------|-----------------|------------|----------|-----------|
| < 1 GHz | > 100W | LDMOS | 20-40 GHz | HF/VHF high power |
| < 1 GHz | < 100W | LDMOS/Si | 20-40 GHz | Sub-GHz operation |
| 1-4 GHz | > 50W | GaN | 50-100 GHz | LTE/5G sub-6 high power |
| 1-4 GHz | 10-50W | LDMOS | 20-40 GHz | Medium power base stations |
| 1-4 GHz | < 10W | GaAs | 30-60 GHz | Low power applications |
| 4-12 GHz | > 10W | GaN | 50-100 GHz | Mid-band microwave |
| 4-12 GHz | < 10W | GaAs | 30-60 GHz | Low-mid power |
| 12-40 GHz | Any | GaN | 50-100 GHz | 5G mmWave |
| 40-100 GHz | Any | SiGe | 200-300 GHz | W-band |
| > 100 GHz | Any | InP | 300-600 GHz | Sub-THz |

#### **Example Calculations**

```javascript
// Example 1: LTE Base Station
Frequency: 1.805 GHz
P3dB: 55.3 dBm (340W)
Required fT: 5 × 1.805 = 9.03 GHz
→ Selected: GaN HEMT (fT: 50-100 GHz ✓)

// Example 2: 5G mmWave
Frequency: 28 GHz
P3dB: 40 dBm (10W)
Required fT: 5 × 28 = 140 GHz
→ Selected: GaN HEMT (fT: 50-100 GHz minimum)
   OR SiGe HBT (fT: 200-300 GHz ✓✓)

// Example 3: Sub-6 GHz Small Cell
Frequency: 3.5 GHz
P3dB: 37 dBm (5W)
Required fT: 5 × 3.5 = 17.5 GHz
→ Selected: GaAs pHEMT (fT: 30-60 GHz ✓)
```

---

## 📊 Passive Loss Estimation

### **Frequency-Dependent Loss Curves**

Based on realistic industry data:

#### **Matching Networks**
```
< 2 GHz:   0.1 - 0.3 dB (low loss, primarily TL)
2-6 GHz:   0.15 - 0.4 dB (moderate loss)
6-30 GHz:  0.25 - 0.6 dB (increasing conductor/dielectric loss)
> 30 GHz:  0.5 - 1.0 dB (high mmWave losses)
```

#### **Splitters (Wilkinson/Hybrid)**
```
< 6 GHz:   0.2 dB (ideal Wilkinson)
6-30 GHz:  0.3 + 0.01×freq dB
> 30 GHz:  0.5 + 0.02×freq dB
```

#### **Combiners**
```
< 6 GHz:   0.25 dB
6-30 GHz:  0.35 + 0.01×freq dB
> 30 GHz:  0.6 + 0.02×freq dB
```

#### **Doherty Combiners**
```
Loss = Matching_Loss + 0.1 dB (λ/4 transformer + combining point)
```

---

## ⚙️ Gain Distribution Algorithm

### **Stage Count Determination**

```javascript
Total Gain < 15 dB   → 1 stage  (PA only)
15-30 dB             → 2 stages (Driver + PA)
30-45 dB             → 3 stages (Pre-driver + Driver + PA)
> 45 dB              → 4 stages (Multi-stage)
```

### **Distribution Heuristics**

- **Individual stage gain cap**: 18 dB (stability limit)
- **Driver minimum**: 10 dB (adequate drive capability)

#### **Example: 41.5 dB Total Gain**
```
Stage Count: 3 (Pre-driver + Driver + PA)

Distribution:
  Pre-driver: 15.0 dB
  Driver:     15.0 dB
  PA:         11.5 dB
  TOTAL:      41.5 dB ✓
```

---

## 🔋 Power Cascade Calculation

### **Methodology**

Works **backwards** from output power using gain stages:

```
Pin = Pout - Gain
```

#### **Example: Single Doherty**

```
Specifications:
  P3dB: 55.3 dBm (final output)
  Gain: 41.5 dB (total)

Cascade (backwards):
Stage 3 (PA):         Pin= 43.8 dBm → [+11.5dB] → Pout= 55.3 dBm ✓
Stage 2 (Driver):     Pin= 28.8 dBm → [+15.0dB] → Pout= 43.8 dBm
Stage 1 (Pre-driver): Pin= 13.8 dBm → [+15.0dB] → Pout= 28.8 dBm

Required Input Power: 13.8 dBm
```

---

## 🎨 Bias Class Selection

### **Doherty Topology** (Implemented)
```
Main PA:  Class AB  (linearity + efficiency balance)
Aux PA:   Class C   (maximum efficiency, turns on at backoff)
Driver:   Class A   (linear drive, low distortion)
```

### **Conventional Topology** (Future)
```
Efficiency Target < 35%:  Class A  (max linearity)
35-48%:                   Class AB (balanced)
48-55%:                   Class B  (higher efficiency)
> 55%:                    Class C  (max efficiency)
```

---

## 📈 PAE Estimation

### **Base PAE by Bias Class**

```
Class A:  30% (high linearity, low efficiency)
Class AB: 45% (balanced)
Class B:  50% (higher efficiency)
Class C:  55% (maximum efficiency)
```

### **Doherty Enhancement**
```
Main PA (AB): 50% (Doherty load modulation benefit)
Aux PA (C):   45% (conduction angle effect)
```

### **Frequency Derating**

```javascript
freq < 10 GHz:   PAE × 1.0   (no degradation)
10-30 GHz:       PAE × 0.9   (10% reduction)
> 30 GHz:        PAE × 0.85  (15% reduction, mmWave)
```

#### **Example**
```
Class AB @ 1.8 GHz:  45% × 1.0 = 45%
Class AB @ 28 GHz:   45% × 0.9 = 40.5%
```

---

## 🚀 How to Use (Step-by-Step)

### **Workflow**

```
1. Load Template → 2. Set Specs → 3. Apply Specs → 4. Calculate → 5. Verify
```

### **Detailed Steps**

#### **Step 1: Load a Template**
- Go to **Architecture Templates** (top sidebar)
- Click **"Single Driver Doherty"**
- Template loads with default hardcoded values

#### **Step 2: Set Your Specifications**
- Expand **"Specifications"** box (right sidebar)
- Enter your target specs:
  ```
  Frequency:      1805 MHz  (or your band)
  Supply Voltage: 30 V
  Gain:           41.5 dB
  P3dB:           55.3 dBm
  Efficiency:     47%
  ```

#### **Step 3: Apply Specifications**
- Click **"Apply Specs to Lineup ↓"** button
- Wait for confirmation dialog showing:
  - Technology selected
  - Frequency (GHz)
  - Power (dBm)
  - Gain (dB)
- All components update automatically

#### **Step 4: Calculate Lineup**
- Scroll to **"Calculation Results"** box
- Click **"Calculate Lineup"** button
- Review results:
  - Total gain
  - Output power
  - System PAE
  - Stage-by-stage breakdown

#### **Step 5: Verify Against Specs**
- Compare calculation results with target specs
- Check:
  - ✓ Total gain matches spec_gain?
  - ✓ Final Pout matches spec_p3db?
  - ✓ Efficiency near spec_efficiency?

---

## 🧪 Test Cases

### **Test 1: LTE Band 3 (1.8 GHz)**
```yaml
Input Specs:
  Frequency: 1805 MHz
  P3dB: 55.3 dBm
  Gain: 41.5 dB
  Vdd: 30V
  Efficiency: 47%

Expected Results:
  Technology: GaN HEMT
  Stages: 2 (Driver + PA)
  Driver: 15 dB gain, ~29 dBm out
  Main PA: 26.5 dB gain, 55.3 dBm out, Class AB
  Aux PA: 26.5 dB gain, 52 dBm out, Class C
  Passive Losses: ~0.2 dB (matching), ~0.2 dB (splitter/combiner)

Validation:
  ✓ Total gain = 41.5 ± 0.5 dB
  ✓ Pout = 55.3 ± 0.5 dBm
  ✓ PAE > 45% (Doherty benefit)
```

### **Test 2: 5G Sub-6 (2.6 GHz)**
```yaml
Input Specs:
  Frequency: 2600 MHz
  P3dB: 50 dBm
  Gain: 35 dB
  Vdd: 28V
  Efficiency: 50%

Expected Results:
  Technology: GaN HEMT
  Stages: 2 (Driver + PA)
  Driver: 17.5 dB gain, ~32.5 dBm out
  Main PA: 17.5 dB gain, 50 dBm out, Class AB
  Aux PA: 17.5 dB gain, 47 dBm out, Class C
  Passive Losses: ~0.25 dB

Validation:
  ✓ Total gain = 35 ± 0.5 dB
  ✓ Pout = 50 ± 0.5 dBm
  ✓ PAE > 48%
```

### **Test 3: 5G mmWave (28 GHz)**
```yaml
Input Specs:
  Frequency: 28000 MHz
  P3dB: 40 dBm
  Gain: 25 dB
  Vdd: 12V
  Efficiency: 35%

Expected Results:
  Technology: GaN HEMT or SiGe HBT
  Stages: 2 (Driver + PA)
  Driver: 12.5 dB gain, ~27.5 dBm out
  PA: 12.5 dB gain, 40 dBm out, Class AB
  Passive Losses: ~0.6 dB (higher at mmWave)

Validation:
  ✓ Total gain = 25 ± 1.0 dB (higher tolerance at mmWave)
  ✓ Pout = 40 ± 0.5 dBm
  ✓ PAE > 30% (mmWave derating)
```

---

## 📁 Files Modified

### **1. R/app.R**
- **Lines 884-898**: Added two action buttons ("Apply Specs to Lineup", "Update Global Params")
- **Lines 2947-3030**: Added R observers for specification button clicks
- **Functionality**: Collects specs, sends to JavaScript via `sendCustomMessage`

### **2. www/js/pa_lineup_canvas.js**
- **Lines 7350-7650**: Added specification-driven design utilities
  - `selectTechnology()`: Technology selection algorithm
  - `estimatePassiveLoss()`: Frequency-dependent loss curves
  - `distributeGain()`: Gain distribution across stages
  - `calculateP1dB()`: P1dB from P3dB
  - `estimatePAE()`: PAE based on bias class
  - `selectBiasClass()`: Bias class selection
  - `calculatePowerCascade()`: Power cascade calculations

- **Lines 6505-6650**: Added `applySpecsToComponents()` function
  - Identifies transistor roles (driver, main PA, aux PA)
  - Applies technology selection
  - Updates gain/power based on cascade
  - Updates passive losses
  - Triggers canvas redraw

- **Lines 6760-6790**: Added message handler `applySpecsToLineup`
  - Receives specs from R
  - Validates canvas state
  - Calls `applySpecsToComponents()`

---

## ⚠️ Known Limitations (POC)

### **Current Scope**
- ✅ Single Doherty topology only
- ✅ 2-stage architecture (Driver + PA)
- ✅ Main/Aux PA identification by label

### **Not Yet Implemented**
- ⏳ Other topologies (Conventional, Balanced, etc.)
- ⏳ 3+ stage architectures (Pre-driver support)
- ⏳ Validation panel showing spec compliance
- ⏳ "Auto-Fix" for spec mismatches
- ⏳ P5dB / PxdB configurable compression points
- ⏳ Bandwidth considerations for specifications
- ⏳ Template generation from specs (currently adapts existing)

---

## 🔄 Next Steps (Phase 3-4)

### **Immediate (Next Session)**
1. Test with real spec values provided by user
2. Verify calculations match expected results
3. Add validation panel showing:
   ```
   Target Gain:   41.5 dB
   Achieved Gain: 41.2 dB ✓
   Delta:         -0.3 dB (within tolerance)
   ```

### **Near-Term (Week 1-2)**
1. Extend to other Doherty variants:
   - Dual Driver Doherty
   - Inverted Doherty
   - Symmetric Doherty
2. Add 3-stage support (Pre-driver + Driver + PA)
3. Implement bandwidth-based loss adjustments

### **Medium-Term (Week 3-4)**
1. Extend to non-Doherty topologies:
   - Conventional (single PA)
   - Balanced (parallel PAs)
   - Corporate combining
2. Add template generation from scratch:
   - User enters specs first
   - System recommends topology
   - Auto-generates optimized template

---

## 📚 Implementation Reference

### **Key Functions** (JavaScript)

```javascript
// Core utilities (www/js/pa_lineup_canvas.js)

selectTechnology(freq_ghz, pout_dbm, vdd)
  → Returns: {technology, rationale, required_fT}

estimatePassiveLoss(component_type, freq_ghz, length_lambda)
  → Returns: {loss, rationale}

distributeGain(total_gain_db, topology)
  → Returns: {num_stages, stages: [{name, gain, type}]}

calculatePowerCascade(pout_final_dbm, gain_stages)
  → Returns: [{stage, gain, pin, pout}]

estimatePAE(bias_class, topology, freq_ghz)
  → Returns: pae_percentage

selectBiasClass(efficiency_target, topology, pa_role)
  → Returns: bias_class_string

applySpecsToComponents(specs)
  → Updates all components in window.paCanvas
```

### **R Observers** (R/app.R)

```r
# Apply specs to global params only
observeEvent(input$apply_specs_to_global, {
  updateNumericInput(session, "global_frequency", value = freq_ghz)
})

# Apply specs to lineup (full adaptation)
observeEvent(input$apply_specs_to_lineup, {
  specs <- list(frequency_ghz, p3db, gain, ...)
  session$sendCustomMessage("applySpecsToLineup", specs)
})
```

---

## 🎓 Academic References

### **Technology Selection**
- **fT/fmax requirements**: Chapter 1, Section 2.2.4-2.2.5, Figure 1.2c
- **Rule of thumb**: fT > 5 × fop (Frequency Planning tab)

### **Passive Loss Curves**
- Transmission line losses: Pozar, "Microwave Engineering", Chapter 2
- Wilkinson combiner: Wilkinson, IRE Trans. MTT, 1960
- Hybrid couplers: Mongia et al., "RF and Microwave Coupled-Line Circuits"

### **Doherty PA Design**
- Load modulation: Doherty, PIRE, 1936
- Modern implementations: Cripps, "Advanced Techniques in RF Power Amplifier Design"

---

## ✅ Success Criteria (POC)

### **Functional Requirements** ✅
- [x] Button-triggered spec application
- [x] Technology selection based on freq+power
- [x] Automatic gain distribution
- [x] Power cascade calculation
- [x] Component parameter updates
- [x] Passive loss estimation

### **Accuracy Requirements** 🔄 (Testing Needed)
- [ ] Gain distribution within ±1 dB of optimal
- [ ] Technology selection matches manual selection
- [ ] Losses within ±0.2 dB of measured data
- [ ] PAE estimates within ±5% of typical values

### **Usability Requirements** ✅
- [x] Single-click application
- [x] Confirmation dialog with summary
- [x] Console logging for debugging
- [x] Compatible with existing workflows

---

**Status**: ✅ **POC COMPLETE - READY FOR TESTING**

**Next Action**: User testing with real specification values and lineup calculations

