# Tx_Baseline Project - Background Overview

**Extraction Date**: February 1, 2026  
**Source Files**: 4 PDFs from `01_Background_overview/`  
**Status**: 🔄 Extraction in progress

---

## Document Sources

1. **01_Base_line_overview.pdf** - Initial project overview
2. **02_Deep_dive_MUC_v0_general overview of Baseline.pdf** - Technical deep dive
3. **03_PAM2p0_Steering_2022-09-29_slides.pdf** - Steering committee decisions
4. **04_TX_Baseline_overview_Jan_2023.pdf** - Final project status

---

## 1. Project Context & Motivation

### Business Drivers
**Why was Tx_Baseline project initiated?**
- [ ] TBD: Extract from 01_Base_line_overview.pdf
- Market requirements for 5G base stations
- Need for optimized GaN transistor selection
- Cost/performance targets

### Technical Objectives
**What were the primary goals?**
- [ ] TBD: Extract from overview documents
- Select optimal GaN transistor for PAM_B module
- Characterize multiple device sizes and technologies
- Establish baseline performance metrics
- Create validated device models

### Success Criteria
**How was success defined?**
- [ ] TBD: Extract criteria
- Performance targets: Pout, PAE, Linearity
- Cost constraints
- Manufacturing feasibility
- Schedule milestones

---

## 2. Project Scope

### Devices Under Test
**Which transistors were evaluated?**

| Device Family | Part Numbers | Gate Periphery Range | Technology Node |
|---------------|--------------|----------------------|-----------------|
| T-series GaN | TBD | TBD | TBD |
| R-series GaN | TBD | TBD | TBD |
| LDMOS | TBD | TBD | TBD |

### Frequency Band
- **Target**: TBD GHz (3.3-3.8 GHz expected for 5G)
- **Bandwidth**: TBD MHz
- **Application**: 5G mmWave/Sub-6GHz base station

### Performance Targets

| Parameter | Target Value | Units | Priority |
|-----------|--------------|-------|----------|
| Output Power (Pout) | TBD | dBm | HIGH |
| PAE @ Pout | TBD | % | HIGH |
| Gain | TBD | dB | MEDIUM |
| IM3 | TBD | dBc | HIGH |
| ACPR | TBD | dBc | HIGH |
| EVM | TBD | % | MEDIUM |

**Note**: Extract actual values from 5G_Frontend_requirements PDF

---

## 3. Design Methodology

### DOE (Design of Experiments) Strategy
**How was the exploration structured?**

#### Variables Investigated
1. **Device Technology**: TBD (T-series, R-series, LDMOS)
2. **Device Size**: TBD (range: 2.4mm - 12mm)
3. **Bias Point**: TBD (Vds, Iq)
4. **Matching Strategy**: TBD (harmonic control, conjugate match)
5. **Assembly**: TBD (wire-bond variants, thermal management)

#### DOE Phases
- [ ] **Phase 1**: Baseline establishment (DOE1)
- [ ] **Phase 2**: Technology alternatives (DOE6, DOE7, DOE9)
- [ ] **Phase 3**: Size optimization (DOE11, DOE13)
- [ ] **Phase 4**: Final refinement (DOE15, DOE16, DOE17)

### Simulation Tools
- [ ] TBD: ADS (Advanced Design System)?
- [ ] TBD: Other EDA tools?

### Measurement Equipment
- [ ] TBD: VNA for S-parameters?
- [ ] TBD: Load-pull system (FOCUS, ANT)?
- [ ] TBD: Signal analyzers for linearity?

---

## 4. Project Timeline

### Key Milestones
- [ ] **Project Kickoff**: TBD (2022?)
- [ ] **Simulation Phase**: TBD
- [ ] **Measurement Campaign**: TBD
- [ ] **Downselection Decision**: TBD
- [ ] **Final Report**: TBD (Jan 2023 based on filename)

### DOE Build Schedule
| Build | DOE | Timeline | Status |
|-------|-----|----------|--------|
| Build 1 | DOE1 | TBD | TBD |
| Build 2c | - | TBD | TBD |
| Build 3 | DOE6 | TBD | TBD |
| Build 4 | DOE7 | TBD | TBD |
| Build 5 | DOE9 | TBD | TBD |
| Build 6 | DOE11 | TBD | TBD |
| Build 7 | DOE13 | TBD | TBD |
| Build 8 | DOE15/16 | TBD | TBD |
| Build 9 | DOE17 | TBD | TBD |

---

## 5. Organization & Team

### Stakeholders
- [ ] TBD: Project lead?
- [ ] TBD: Design engineers?
- [ ] TBD: Measurement team?
- [ ] TBD: Steering committee members?

### Collaboration
- [ ] TBD: Internal teams involved?
- [ ] TBD: External partners?
- [ ] TBD: Foundry/fab coordination?

---

## 6. Technical Approach

### Simulation Workflow
1. [ ] **Device Model**: TBD - Large-signal model source?
2. [ ] **Matching Network Design**: TBD - Approach?
3. [ ] **Load-Pull Analysis**: TBD - Contour optimization?
4. [ ] **Harmonic Termination**: TBD - Strategies?

### Measurement Workflow
1. [ ] **DC Characterization**: TBD - Procedure?
2. [ ] **S-Parameter Measurement**: TBD - Setup?
3. [ ] **Load-Pull Optimization**: TBD - System used?
4. [ ] **Linearity Testing**: TBD - Modulation schemes?

### Downselection Criteria
**How was the final device selected?**
- [ ] TBD: Weighted scoring system?
- [ ] TBD: Performance vs cost trade-off?
- [ ] TBD: Manufacturing considerations?

**Weighting Factors** (if available):
| Criterion | Weight | Rationale |
|-----------|--------|-----------|
| PAE | TBD% | TBD |
| Pout | TBD% | TBD |
| Linearity (IM3) | TBD% | TBD |
| Gain | TBD% | TBD |
| Cost | TBD% | TBD |
| Size | TBD% | TBD |

---

## 7. Key Findings (High-Level)

### Technology Comparison
- [ ] **GaN T-series vs R-series**: TBD
- [ ] **GaN vs LDMOS**: TBD
- [ ] **Optimal technology recommendation**: TBD

### Size Optimization
- [ ] **Smallest viable size**: TBD mm
- [ ] **Largest tested size**: TBD mm
- [ ] **Optimal size selected**: TBD mm
- [ ] **Size vs performance trade-off**: TBD

### Performance Highlights
- [ ] **Best PAE achieved**: TBD%
- [ ] **Best linearity (IM3)**: TBD dBc
- [ ] **Best Pout**: TBD dBm
- [ ] **Winner**: DOE# TBD

---

## 8. Challenges & Lessons Learned

### Technical Challenges
- [ ] TBD: Stability issues?
- [ ] TBD: Thermal management?
- [ ] TBD: Matching network complexity?
- [ ] TBD: Measurement correlation?

### Process Learnings
- [ ] TBD: DOE effectiveness?
- [ ] TBD: Simulation accuracy?
- [ ] TBD: Schedule risks?

---

## 9. Integration with PAM_B Project

### Handoff to PA Module Design
- [ ] **Selected Device**: TBD (DOE# winner)
- [ ] **Design Files Provided**: TBD
- [ ] **Validated Models**: TBD
- [ ] **Performance Specifications**: TBD

### Design Constraints for Integration
- [ ] **Package Selection**: Minipac V2
- [ ] **Thermal Interface**: TBD
- [ ] **Bias Network Requirements**: TBD
- [ ] **Matching Network Considerations**: TBD

---

## 10. References & Documentation

### Related Documents
- [ ] 5G_Frontend_requirements_PAM2p0+_external_2v1.pdf (Specifications)
- [ ] All DOE build reports (DOE1-DOE17)
- [ ] Measurement reports (03_Measurements/)
- [ ] Device models (04_Model/)
- [ ] Final baseline results (07_PCB-pac/)

### Key Figures to Extract
- [ ] **Project flowchart**: Page TBD in which PDF?
- [ ] **DOE strategy diagram**: Page TBD
- [ ] **Technology comparison table**: Page TBD
- [ ] **Timeline/Gantt chart**: Page TBD

---

## 11. Extraction Notes

### PDF Review Status
| Document | Pages | Reviewed | Key Content | Priority Sections |
|----------|-------|----------|-------------|-------------------|
| 01_Base_line_overview.pdf | TBD | ⏳ | TBD | TBD |
| 02_Deep_dive_MUC_v0_general... | TBD | ⏳ | TBD | TBD |
| 03_PAM2p0_Steering... | TBD | ⏳ | TBD | TBD |
| 04_TX_Baseline_overview_Jan... | TBD | ⏳ | TBD | TBD |

### Data Extraction Workflow
1. [ ] Open each PDF in sequence
2. [ ] Scan table of contents / outline
3. [ ] Extract project objectives and scope
4. [ ] Extract performance targets and specifications
5. [ ] Extract DOE strategy and timeline
6. [ ] Extract key findings and recommendations
7. [ ] Note important figures with page numbers
8. [ ] Cross-reference with other documents

---

## 12. Integration with Chapter 1

### Chapter 1 Section Mapping
- **Section 1.1 (Introduction)**: Use project motivation and scope
- **Section 1.2 (GaN Fundamentals)**: Reference technology comparison
- **Section 1.3 (RF Characterization)**: Use measurement methodology
- **Section 1.4 (Downselection)**: PRIMARY - Use DOE strategy and results
- **Section 1.8 (Summary)**: Use key findings and lessons learned

### Evidence Requirements
- [ ] Project context statement for Chapter 1.1
- [ ] Technology comparison table for Chapter 1.2
- [ ] Measurement setup description for Chapter 1.3
- [ ] DOE strategy narrative for Chapter 1.4
- [ ] Lessons learned checklist for Chapter 1.8

---

**Status**: 🔄 Ready for manual PDF review  
**Estimated Time**: 2-3 hours for all 4 documents  
**Next Action**: Open 01_Base_line_overview.pdf and begin extraction  
**Last Updated**: February 1, 2026

