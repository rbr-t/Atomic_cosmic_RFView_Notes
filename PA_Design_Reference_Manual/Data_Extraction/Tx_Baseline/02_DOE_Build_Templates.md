# DOE Build Extraction Templates

**Project**: Tx_Baseline DOE Systematic Exploration  
**Purpose**: Extract design methodology and results from 9 DOE builds  
**Builds**: DOE1, DOE6, DOE7, DOE9, DOE11, DOE13, DOE15, DOE16, DOE17  

---

## Build Naming Convention

Format: **Build_X_DOEY_[Details]**

Where:
- **X**: Sequential build number (1-9)
- **Y**: DOE number (1, 6, 7, 9, 11, 13, 15, 16, 17)
- **Details**: Device model, size, technology

---

## DOE Build Summary Table

| Build | DOE | Device | Technology | Gate Width | Key Focus |
|-------|-----|--------|------------|-----------|-----------|
| 1 | DOE1 | T9095A | GaN HEMT | 12mm | Reference/baseline |
| 2c | - | Various | Comparison | - | Lgit vs Access study |
| 3 | DOE6 | T9095A | GaN HEMT | 12mm | Chip-n-wire variant |
| 4 | DOE7 | T9507B | GaN HEMT | 2.4mm | Small device |
| 5 | DOE9 | R9505 | GaN HEMT | 11.52mm | Large device |
| 6 | DOE11 | T9504 | GaN HEMT | 3.84mm | Medium device |
| 7 | DOE13 | R9505 | GaN HEMT | 6.4mm | Medium-large device |
| 8 | DOE15 | T6083A | LDMOS | 6×380μm | LDMOS baseline |
| 8 | DOE16 | R6051A | GaN HEMT | 8×400μm (3.2mm) | Optimized GaN |
| 9 | DOE17 | T9501R | GaN HEMT | 2.4mm | Latest technology |

---

## Extraction Template (Per DOE Build)

### File Header
```markdown
## DOEX: [Device] [Size] [Technology]

**PDF**: [filename]
**Path**: 02_Design/06_Simulations/Build_X_DOEX/
**Pages**: [count]
**Date**: [if available]
```

### 1. Build Overview
- **Objective**: Why this build/configuration?
- **Technology**: GaN family, generation, process
- **Device Size**: Total gate periphery
- **Design Iteration**: First build or refinement?

### 2. Device Selection
- **Model Number**: Full part number
- **Technology Node**: Process generation
- **Key Specifications**:
  - Breakdown voltage (Vds_max)
  - Current density (Id_max)
  - Gate periphery per finger
  - Number of fingers
  - Total width
- **Selection Rationale**: Why this device?

### 3. Bias Conditions
- **Drain Voltage (Vds)**: Operating voltage
- **Quiescent Current (Iq)**: Class-AB bias point
- **Gate Voltage (Vgs)**: Bias network
- **Operating Class**: Class-AB, -B, -C?
- **Optimization**: How bias was chosen

### 4. Matching Network Design
- **Input Match**:
  - Topology (L-match, Pi, Tee?)
  - Component values
  - Target impedance
  - Bandwidth achieved
  
- **Output Match**:
  - Topology
  - Component values
  - Load impedance (ZL)
  - Harmonic terminations
  
- **Stability Network**:
  - RC stabilization
  - Terminations
  - K-factor achieved

### 5. Simulation Results
- **Small-Signal (S-Parameters)**:
  - S21 (Gain): [X] dB @ 3.5 GHz
  - S11 (Input return loss): [Y] dB
  - S22 (Output return loss): [Z] dB
  - K-factor: [value]
  - μ-factor: [value]
  
- **Large-Signal Performance**:
  - Pout @ 1dB compression: [X] dBm
  - Pout @ 3dB back-off: [Y] dBm
  - PAE @ Pout: [Z] %
  - PAE @ back-off: [W] %
  - Gain @ Pout: [V] dB
  - IM3 (two-tone): [A] dBc
  
- **Load-Pull Contours**:
  - Optimal load impedance: [ZL_opt]
  - PAE vs Pout trade-off
  - Contour characteristics

### 6. Key Design Decisions
- **Trade-offs Made**:
  - Size vs efficiency vs linearity
  - Bandwidth vs performance
  - Stability vs gain
  
- **Optimizations**:
  - What was optimized?
  - Optimization method
  - Results achieved

### 7. Important Figures
- **Fig X**: Load-pull contours (Page Y)
- **Fig Z**: Pout/PAE vs Pin (Page W)
- **Fig A**: Stability circles (Page B)
- **Fig C**: Matching network schematic (Page D)
- **Fig E**: Simulated IM3 (Page F)

### 8. Key Insights & Learnings
- **What Worked**:
  - Successful aspects
  - Meeting targets
  
- **Challenges**:
  - Issues encountered
  - Limitations found
  
- **Recommendations**:
  - Next steps suggested
  - Improvements proposed

### 9. Comparison to Specifications
- **Pout**: Target vs achieved
- **PAE**: Target vs achieved
- **IM3**: Target vs achieved
- **Verdict**: Pass/Fail/Marginal?

### 10. Cross-References
- **Related Builds**: DOE comparison
- **Measurement Data**: If tested
- **Downselection Impact**: Selected or rejected?

---

## DOE Progression Analysis

### Technology Comparison
**GaN Families Explored**:
1. **T-series (Triquint heritage)**:
   - T9095A (12mm) - DOE1, DOE6
   - T9507B (2.4mm) - DOE7
   - T9504 (3.84mm) - DOE11
   - T9501R (2.4mm) - DOE17
   
2. **R-series (Recent/refined?)**:
   - R9505 (11.52mm, 6.4mm) - DOE9, DOE13
   - R6051A (3.2mm) - DOE16

3. **LDMOS Baseline**:
   - T6083A (6×380μm) - DOE15

### Size Progression
**Small devices (2.4-3.84mm)**:
- DOE7: T9507B 2.4mm
- DOE11: T9504 3.84mm  
- DOE16: R6051A 3.2mm
- DOE17: T9501R 2.4mm

**Medium devices (6.4mm)**:
- DOE13: R9505 6.4mm

**Large devices (11.52-12mm)**:
- DOE1: T9095A 12mm
- DOE6: T9095A 12mm (chip-n-wire)
- DOE9: R9505 11.52mm

### Evolution Pattern
1. **Phase 1**: Large device baseline (DOE1, 12mm)
2. **Phase 2**: Assembly comparison (Build 2c)
3. **Phase 3**: Alternative large device (DOE6, chip-n-wire)
4. **Phase 4**: Size scaling down (DOE7, 2.4mm)
5. **Phase 5**: Alternative large (DOE9, 11.52mm)
6. **Phase 6**: Medium device (DOE11, 3.84mm)
7. **Phase 7**: Medium-large (DOE13, 6.4mm)
8. **Phase 8**: LDMOS comparison + GaN optimization (DOE15, DOE16)
9. **Phase 9**: Latest technology small (DOE17, 2.4mm)

**Hypothesis**: Systematic exploration from large (cost/complexity) to smaller, more optimized devices, with technology family comparisons to find best performance/cost trade-off.

---

## Extraction Priority

### Week 2 Focus (5 builds)
1. ✅ **DOE1** (Reference baseline) - Critical
2. ✅ **DOE9** (Large R9505) - Alternative technology
3. ✅ **DOE11** (Medium T9504) - Mid-range
4. ✅ **DOE15** (LDMOS) - Technology comparison
5. ✅ **DOE17** (Latest GaN) - Final iteration

### Week 3 Completion (4 builds)
6. **DOE6** (Chip-n-wire)
7. **DOE7** (Small T9507B)
8. **DOE13** (Medium-large R9505)
9. **DOE16** (Optimized 3.2mm)
10. **Build 2c** (Assembly comparison)

---

## Data Consolidation

After individual extraction, create:

### Comparative Analysis Table
| DOE | Device | Size (mm) | Vds (V) | Iq (mA) | Pout (dBm) | PAE (%) | IM3 (dBc) | Rank |
|-----|--------|-----------|---------|---------|------------|---------|-----------|------|
| 1 | T9095A | 12.0 | TBD | TBD | TBD | TBD | TBD | ? |
| 6 | T9095A | 12.0 | TBD | TBD | TBD | TBD | TBD | ? |
| 7 | T9507B | 2.4 | TBD | TBD | TBD | TBD | TBD | ? |
| 9 | R9505 | 11.52 | TBD | TBD | TBD | TBD | TBD | ? |
| 11 | T9504 | 3.84 | TBD | TBD | TBD | TBD | TBD | ? |
| 13 | R9505 | 6.4 | TBD | TBD | TBD | TBD | TBD | ? |
| 15 | T6083A | 2.28 | TBD | TBD | TBD | TBD | TBD | ? |
| 16 | R6051A | 3.2 | TBD | TBD | TBD | TBD | TBD | ? |
| 17 | T9501R | 2.4 | TBD | TBD | TBD | TBD | TBD | ? |

### Trade-off Plots (Using Our Tools!)
1. **Size vs PAE**: Show scaling trends
2. **Size vs Pout**: Confirm expected relationship
3. **PAE vs Linearity (IM3)**: Classic trade-off
4. **Technology Comparison**: T-series vs R-series vs LDMOS
5. **Pareto Front**: Optimal designs identified

### Design Insights Summary
- **Optimal Size Range**: Based on performance/cost
- **Technology Winner**: GaN family selection
- **Bias Point Strategy**: Efficiency vs linearity balance
- **Matching Methodology**: Successful topologies
- **Downselection Rationale**: Why final choice?

---

## Integration with Automation Framework

### Apply Our Tools
1. **Linearity Optimizer**:
   - Input: Extracted device data
   - Optimize: Bias point and ZL for each DOE
   - Output: Predicted sweet spots
   
2. **Trade-off Plotter**:
   - Input: DOE performance table
   - Generate: 6-panel analysis
   - Interactive: 3D design space
   
3. **Manufacturing Analysis**:
   - Size vs yield
   - Cost estimation
   - Volume production readiness

---

**Status**: Templates ready  
**Next**: Begin DOE1 extraction  
**Timeline**: 5 builds by Feb 5, remaining by Feb 12
