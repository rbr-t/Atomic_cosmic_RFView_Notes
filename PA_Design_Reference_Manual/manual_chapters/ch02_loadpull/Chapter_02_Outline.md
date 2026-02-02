# Chapter 2: PA Design Methodology - Content Outline

**Based on**: IFX Tx_Baseline & PAM_B Projects  
**Created**: February 1, 2026  
**Status**: Ready for content development

---

## Chapter Overview

**Goal**: Document the systematic PA design process from requirements to architecture selection, using actual IFX project workflows.

**Evidence Sources**:
- Tx_Baseline: `01_Background_overview/`, `02_Design/`
- PAM_B: `01_Overview/`, `03_Design/01_Performance/`

---

## 2.1 Requirements Analysis

### 2.1.1 System-Level Requirements
**Concept**: Translating 5G base station specifications to PA requirements

**Content to Extract**:
- [ ] 5G NR system context (PAM_B overview)
- [ ] Frequency bands: 3.3-3.8 GHz (n77/n78)
- [ ] Power levels: Average, peak, backoff requirements
- [ ] Efficiency targets: PAE @ various backoff levels
- [ ] Linearity requirements: ACLR, EVM for 5G NR

**Data Sources**:
- `Tx_Baseline/02_Design/04_Specifications/5G_Frontend_requirements_PAM2p0+_external_2v1.pdf`
- `PAM_B/01_Overview/` specifications

**Tables to Create**:
- Table 2.1: 5G NR System Requirements
- Table 2.2: PA Specification Translation

### 2.1.2 Link Budget Analysis
**Theory**: RF link budget fundamentals

**Content**:
- [ ] Transmit power requirements
- [ ] PA contribution to system efficiency
- [ ] Thermal dissipation constraints
- [ ] Cost/performance trade-offs

**Figures**:
- Figure 2.1: RF transmit chain block diagram
- Figure 2.2: Power budget breakdown

### 2.1.3 Trade-off Framework
**Critical Design Choices**:
- [ ] Efficiency vs Linearity
- [ ] Power vs Size (transistor periphery)
- [ ] Cost vs Performance
- [ ] Complexity vs Manufacturability

**Data from**:
- Tx_Baseline DOE comparison (Chapter 1 data)
- PAM_B design decisions

---

## 2.2 Transistor Selection & Characterization

### 2.2.1 Device Technology Options
**Concept**: Comparing power transistor technologies

**Content**:
- [ ] LDMOS characteristics
- [ ] GaN advantages and challenges
- [ ] Technology selection criteria

**Evidence**:
- Tx_Baseline: DOE15 (LDMOS) vs DOE1-17 (GaN)
- Technology comparison from downselection

**Table 2.3**: Technology Comparison Matrix
| Parameter | LDMOS | GaN (T-series) | GaN (R-series) | Winner |
|-----------|-------|----------------|----------------|--------|
| Frequency | TBD | TBD | TBD | TBD |
| Power Density | TBD | TBD | TBD | TBD |
| Efficiency | TBD | TBD | TBD | TBD |
| Linearity | TBD | TBD | TBD | TBD |
| Cost | TBD | TBD | TBD | TBD |

### 2.2.2 Load-Pull Characterization
**Theory**: Load-pull fundamentals

**Content**:
- [ ] Load-pull system setup
- [ ] Contour interpretation (PAE, Pout, Gain, IM3)
- [ ] Optimal impedance determination
- [ ] Source-pull considerations

**Evidence**:
- Tx_Baseline load-pull data from DOE builds
- `03_Measurements/01_LP_optimization_Procedure/`

**Figures**:
- Figure 2.3: Load-pull contour examples (from DOE1)
- Figure 2.4: Optimal load impedance vs frequency
- Figure 2.5: PAE vs Pout trade-off

### 2.2.3 Device Sizing Strategy
**Concept**: Selecting gate periphery for power target

**Content**:
- [ ] Power scaling with device size
- [ ] Thermal considerations
- [ ] Impedance transformation difficulty
- [ ] Cost implications

**Evidence**:
- Tx_Baseline size study: 2.4mm to 12mm
- DOE1 (12mm) vs DOE11 (3.84mm) vs DOE17 (2.4mm)

**Figure 2.6**: Size Scaling Analysis
- Pout vs Size
- PAE vs Size  
- Cost vs Size
- Optimal size selection

### 2.2.4 Downselection Process
**Reference Chapter 1.4** - Use Tx_Baseline downselection data

**Content**:
- [ ] Selection criteria and weighting
- [ ] Scoring methodology
- [ ] Final device choice: Winner from DOE comparison
- [ ] Rationale and validation

**Table 2.4**: Device Downselection Matrix (from Chapter 1)

---

## 2.3 Architecture Development

### 2.3.1 PA Architecture Options
**Theory**: Class AB, Doherty, ET, Outphasing

**Content**:
- [ ] Class AB: Simple, moderate efficiency
- [ ] Doherty: High backoff efficiency (PAM_B uses this!)
- [ ] Envelope Tracking: Maximum efficiency
- [ ] Outphasing: Constant envelope

**Comparison Table**:
- Efficiency profile
- Linearity characteristics
- Complexity
- Cost

**Decision for PAM_B**: Doherty architecture selected

### 2.3.2 Multi-Stage Design
**Concept**: Driver + Main + Peak stages

**Content from PAM_B**:
- [ ] Driver stage design
  * Device selection for driver
  * Gain requirements
  * Linearity considerations
  
- [ ] Main transistor (P49)
  * Why P49 selected
  * Operating point
  * Performance optimization
  
- [ ] Peak transistor (P41)
  * Turn-on characteristics
  * Load modulation mechanism
  * Efficiency enhancement

**Data Sources**:
- `PAM_B/03_Design/01_Performance/`
- PAM_B design review documents

**Figures**:
- Figure 2.7: PAM_B Doherty architecture block diagram
- Figure 2.8: Main/Peak transistor load modulation
- Figure 2.9: Efficiency vs backoff (Doherty advantage)

### 2.3.3 Building Block Approach
**Methodology**: Modular design

**Content**:
- [ ] Input matching network
- [ ] Driver stage
- [ ] Splitter network
- [ ] Main branch
- [ ] Peak branch
- [ ] Combiner network
- [ ] Output matching

**Evidence**: PAM_B schematic breakdown

---

## 2.4 Matching Network Design

### 2.4.1 Impedance Transformation Theory
**Fundamentals**:
- [ ] Smith chart review
- [ ] L-section, Pi, T-networks
- [ ] Quality factor and bandwidth
- [ ] Harmonic termination

### 2.4.2 Input Matching Design
**Goal**: 50Ω to device input impedance

**Content**:
- [ ] Input impedance determination (from S-parameters)
- [ ] Stability considerations
- [ ] Gain optimization
- [ ] Bandwidth requirements

**Evidence**: PAM_B input matching network
- Topology
- Component values
- Simulated vs measured performance

### 2.4.3 Output Matching Design
**Goal**: Device output to optimal load impedance

**Content**:
- [ ] Load-pull optimal ZL
- [ ] Power combining considerations (Doherty)
- [ ] Harmonic control
- [ ] Efficiency optimization

**Evidence**: PAM_B output matching
- Main branch matching
- Peak branch matching
- Combiner design

**Figures**:
- Figure 2.10: Input matching network schematic
- Figure 2.11: Output matching and combiner
- Figure 2.12: Simulated impedance transformation

### 2.4.4 Bias Network Design
**Requirements**:
- [ ] DC supply delivery
- [ ] RF isolation
- [ ] Stability (decoupling)
- [ ] Protection (ESD, overcurrent)

**Content**:
- Bias topology (series vs shunt)
- Component selection
- Simulation verification

**Evidence**: PAM_B bias networks

### 2.4.5 Sensitivity Analysis
**Critical**: Component tolerance effects

**Content**:
- [ ] Monte Carlo simulation
- [ ] Critical components identification
- [ ] Design margins
- [ ] Yield prediction

**Data Source**: `PAM_B/03_Design/04_Sensitivity_analysis/`

**Table 2.5**: Sensitivity Analysis Results
| Parameter | Nominal | Tolerance | Performance Impact |
|-----------|---------|-----------|-------------------|
| Inductor L1 | TBD | ±5% | TBD |
| Capacitor C1 | TBD | ±10% | TBD |

---

## 2.5 Design Verification (Pre-Fabrication)

### 2.5.1 Performance Simulation
**Goals**: Verify specs met

**Content**:
- [ ] S-parameter simulation
- [ ] Large-signal power sweep
- [ ] PAE across power and frequency
- [ ] Harmonic analysis

**Data**: `PAM_B/03_Design/01_Performance/`

### 2.5.2 Stability Verification
**Critical**: No oscillations

**Content**:
- [ ] K-factor and µ-factor analysis
- [ ] Conditional stability regions
- [ ] Stabilization techniques

**Data**: `PAM_B/03_Design/03_Stability/`

### 2.5.3 Linearity Pre-Check
**Requirements**: ACLR, EVM targets

**Content**:
- [ ] Two-tone simulation
- [ ] Modulated signal simulation
- [ ] DPD requirements

**Data**: `PAM_B/03_Design/02_Linearity/`

### 2.5.4 Reliability Assessment
**Design for Reliability**:
- [ ] Thermal analysis (junction temperature)
- [ ] Voltage stress check
- [ ] MTTF estimation

**Data**: `PAM_B/03_Design/05_Reliability_analysis/`

---

## Extraction Priority for Chapter 2

### High Priority (Week 3)
1. PAM_B overview and architecture
2. PAM_B performance analysis data
3. Transistor selection from Tx_Baseline (already done in Chapter 1)
4. Matching network designs

### Medium Priority (Week 4)
5. Linearity analysis data
6. Stability analysis data
7. Sensitivity analysis data
8. Reliability analysis data

### Figures to Extract (Week 3-4)
- PAM_B block diagram
- Main/peak transistor schematics
- Matching network schematics
- Performance simulation plots
- Stability analysis plots

---

## Chapter 2 Key Messages

1. **Systematic Approach**: Requirements → Architecture → Device → Matching → Verification
2. **Evidence-Based**: Every decision backed by simulation or measurement
3. **Trade-offs**: No perfect solution, only optimal compromises
4. **Design for Manufacturing**: Consider sensitivity and reliability upfront
5. **Learn from Projects**: PAM_B is a real-world example of this methodology

---

**Status**: Outline complete, ready for data extraction  
**Next Action**: Begin extracting PAM_B design data  
**Integration**: Links to Chapter 1 (transistor selection), Chapter 3 (layout implementation)

