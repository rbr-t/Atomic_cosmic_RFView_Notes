# PA Design Reference Manual - Document Inventory

**Generated:** 2026-02-01  
**Last Updated:** 2026-02-01  
**Status:** Complete - Steps 9/10 & 10/10

---

## Executive Summary

This document provides a complete inventory of all source documents from the Tx_Baseline and PAM_B projects. This inventory serves as the foundation for extracting technical content and building the PA Design Reference Manual.

**Total Projects:** 2  
**Total Documents Identified:** 150+ files across both projects  
**Document Types:** PDF (technical reports, presentations, schematics), Images (PNG), Data files, Configuration files

---

## 1. Tx_Baseline Project (01_Tx_Baseline)

### Project Overview
- **Focus:** GaN discrete transistor design and characterization
- **Purpose:** Downselection of GaN power transistors for PAM-B module
- **Key Output:** Selected transistor specifications and performance data

### 1.1 Background & Overview (01_Background_overview/)
| File | Type | Content Focus |
|------|------|---------------|
| 01_Base_line_overview.pdf | PDF | Project objectives, scope, methodology |
| 02_Deep_dive_MUC_v0_general overview of Baseline.pdf | PDF | Detailed technical overview |
| 03_PAM2p0_Steering_2022-09-29_slides.pdf | PDF | Project steering decisions |
| 04_TX_Baseline_overview_Jan_2023.pdf | PDF | Project status and updates |

**Key Extraction Points:**
- Project motivation and business case
- Technical requirements and specifications
- Initial design assumptions
- Project timeline and milestones

---

### 1.2 Design Phase (02_Design/)

#### 1.2.1 Reference Project (01_Reference_prj_PLP3839/)
| File | Type | Content Focus |
|------|------|---------------|
| Prematch design PLP3839.pdf | PDF | Reference design analysis |

#### 1.2.2 Reference Materials (02_Reference_material_PPT/)
| File | Type | Content Focus |
|------|------|---------------|
| Module Design Rules and Procedures.pdf | PDF | Design guidelines and best practices |

#### 1.2.3 Libraries (03_libraries/)
| File | Type | Content Focus |
|------|------|---------------|
| TXAFE_VIH_full_lib.defs | Config | Component library definitions |
| Minipac Building Blocks - Workflow guide v1p0.pdf | PDF | Design workflow documentation |

#### 1.2.4 Specifications (04_Specifications/)
| File | Type | Content Focus |
|------|------|---------------|
| 5G_Frontend_requirements_PAM2p0+_external_2v1.pdf | PDF | 5G system requirements |

#### 1.2.5 Simulations (06_Simulations/)
**Multiple Design-of-Experiment (DOE) builds covering:**

| Build | DOE | Key Files | Focus Area |
|-------|-----|-----------|------------|
| Build 1 | DOE1 | 03_DOE1_12mm_T9095A_1_P1p5dB_Refined.pdf | Initial 12mm design |
| Build 2c | - | Build 2c_Lgit_vs_Access_fwdBW_vs_revBW.pdf | Assembly comparison |
| Build 3 | DOE6 | 04_Chip_n_wire_12mm_T9095A_1_P1p5dB_15042022.pdf | Chip-and-wire topology |
| Build 4 | DOE7 | 01_2p4mm_T9507B_2_design 10052022.pdf | Compact 2.4mm design |
| Build 5 | DOE9 | 01_Build_5_11p52mm_R9505_A 25052022.pdf | 11.52mm optimization |
| Build 6 | DOE11 | 01_Build_6_3p84mm_P13_T9504_A 12072022.pdf | 3.84mm variant |
| Build 7 | DOE13 | 03_Build_7_6p4mm_R9505_A 12072022.pdf | 6.4mm design |
| Build 8 | DOE15 | DOE15_R6051A_BPCM_3_6X400um_2p4mm_re-design.pdf | LDMOS variant |
| Build 8 | DOE16 | DOE16_R6051A_BPCM_3_8X400um_3p2mm_re-design.pdf | Alternative geometry |
| Build 9 | DOE17 | Build_9_DOE17_T9501R_2p4mm_T9501_R_11082022.pdf | Final refinement |

**Key Extraction Points:**
- Transistor sizing methodology
- Impedance matching network design
- Thermal management strategies
- Trade-offs between size and performance
- Simulation vs. measurement correlation

---

### 1.3 Measurements (03_Measurements/)

#### 1.3.1 Overview (00_Overview/)
| File | Type | Content Focus |
|------|------|---------------|
| 01_DOE4_5_FOCUS vs ANT comparison.pdf | PDF | Test equipment comparison |

#### 1.3.2 Load-Pull Optimization (01_LP_optimzation_Procedure/)
| File | Type | Content Focus |
|------|------|---------------|
| Baseline Loadpull for Comparison of LDMOS & GaN MINIPAC.pdf | PDF | Load-pull methodology |

#### 1.3.3 Test Fixtures (02_Test_Fixture/)
| File | Type | Content Focus |
|------|------|---------------|
| IFX_Nijmegen_test_fixture.pdf | PDF | Fixture design details |
| 20220207_Minipac_fixture.pdf | PDF | Fixture specifications |

#### 1.3.4 Downselection (03_Down_selection/)
**Critical Decision Documents:**

| DOE | File | Decision Point |
|-----|------|----------------|
| Strategy | 00_DOEs measurement strategy.pdf | Overall approach |
| DOE 3 | 01_DOE_3 Downselection.pdf | First downselection |
| DOE 4 | 02_DOE4 Downselection.pdf | Second iteration |
| DOE 5 | 03_DOE5 Downselection.pdf | Third iteration |
| DOE 6 | 04_DOE6 Downselection.pdf | Fourth iteration |
| DOE 6 | 04_DOE6_2 class_C.pdf | Class-C operation analysis |
| DOE 8 | 05_DOE8 Downselection v2.pdf | Fifth iteration |
| DOE 9 | 06_DOE9 Downselection.pdf | Sixth iteration |
| DOE 12 | 07_DOE12 Downselection.pdf | Seventh iteration |
| DOE 14 | 08_DOE14 Downselection.pdf | Eighth iteration |
| DOE 15 | 09_DOE15 Downselection.pdf | Ninth iteration |
| Final | 10_Main_selection.PNG | Final transistor selection |

**Key Extraction Points:**
- Performance metrics (gain, PAE, linearity)
- Measurement procedures and test conditions
- Data analysis methodology
- Decision criteria and rationale
- Final transistor recommendation

---

### 1.4 Modeling (04_Model/)

#### 1.4.1 Model Workshop (02_Workshop/)
| Subfolder | Key Files | Content Focus |
|-----------|-----------|---------------|
| 01_ADS template | - | Simulation template setup |
| 02_Model flow | - | Modeling workflow |
| 03_Model_checklist_specs | - | Model validation criteria |
| 04_ADS_library_wrkspace | Tx_Baseline_Model_library.pdf | Model library documentation |
| 05_workshop PPTs | 05_ADS template user guide_session_5.pdf | Training materials |
| 06_Rgb_Minipac_verification | Report.pdf | Model verification results |

**Key Extraction Points:**
- Transistor modeling methodology
- ADS simulation setup
- Model parameter extraction
- Validation procedures

---

### 1.5 Assembly (05_Assembly/)

#### Subfolders:
- 01_Cross_section_Access/
- 02_Mold_compound/
- 03_Design_Rules/ (Access & LGIT vendors)
- 04_Drawing/ (Review, Assembly plan, AD)
- 05_FA/ (Failure Analysis)

**Key Extraction Points:**
- Package assembly process
- Material selection (mold compound)
- Vendor-specific design rules
- Quality control and FA procedures

---

### 1.6 Minipac Version 2 (06_Minipac_V02/)
| File | Type | Content Focus |
|------|------|---------------|
| Minipac_V2.pdf | PDF | Version 2 specifications |
| 01_Flow Chart of the MiniPac.pdf | PDF | Process flow diagram |

---

### 1.7 PCB Package (07_PCB-pac/)
| File | Type | Content Focus |
|------|------|---------------|
| 20230412 TX module baseline results.pdf | PDF | PCB integration results |

---

## 2. PAM_B Project (02_PAM_B)

### Project Overview
- **Focus:** Two-stage power amplifier module (driver + final)
- **Technology:** GaN transistors (selected from Tx_Baseline)
- **Architecture:** Driver stage + Final stage in single package

### 2.1 Overview (01_Overview/)
#### 01_Flow_chart/
- Project flow diagrams

#### 02_Summary/
- Executive summaries and status reports

**Key Extraction Points:**
- PAM-B architecture
- Project objectives and requirements
- Integration with Tx_Baseline outputs

---

### 2.2 Mini-pac PAM_B Details (02_Mini-pac_PAM_B/)

| Subfolder | Content Focus |
|-----------|---------------|
| 01_Introduction | Project context and motivation |
| 04_Design | Circuit design details |
| 05_Assembly/03_Assembly_drawings | Physical implementation |
| 06_LP_measurements | Load-pull characterization (Anteverta & FOCUS) |
| 07_Model_vs_Measurements | Validation data |
| 08_Conclusion | Key findings |
| 09_Next_steps | Future development |

---

### 2.3 Design Phase (03_Design/)

| Subfolder | Content Focus | Key Documents |
|-----------|---------------|---------------|
| 01_Performance | Power, gain, efficiency metrics | Performance reports |
| 02_Linearity | ACLR, EVM, IMD analysis | Linearity characterization |
| 03_Stability | K-factor, μ-factor analysis | Stability margin reports |
| 04_Sensitivity_analysis | Component tolerance impacts | Sensitivity studies |
| 05_Reliability_analysis | Lifetime, stress testing | Reliability reports |
| 06_Schematic_BOM | Circuit diagrams, BOM | Schematics and component lists |

**Key Extraction Points:**
- Two-stage amplifier design methodology
- Inter-stage matching network design
- Bias network implementation
- Performance optimization techniques

---

### 2.4 Layout (04_Layout/)
- Physical layout files and design reviews

---

### 2.5 Tapeout (05_Tapeout/)

#### 04_Final_layout_TO/
| File | Content Focus |
|------|---------------|
| 01_Final layouts for TO.pdf | Tapeout-ready layouts |
| 02_Layout_snapshots.pdf | Visual documentation |

#### 05_EM_simulations/
| File | Content Focus |
|------|---------------|
| 01_EM_simulation_All_variants.pdf | Electromagnetic analysis |
| 02_EM_simulation_J09.pdf | Variant-specific analysis |
| 03_Impact_molding_material.pdf | Material effects |
| 04_Impact_dielectric_thickness.pdf | Dielectric sensitivity |

**Additional Files:**
- 01_Building blocks update.pdf
- 02_TapeOut strategy_Variants.pdf
- 03_Layout_and_DRC.pdf

**Key Extraction Points:**
- Layout best practices
- EM simulation methodology
- Parasitic extraction and compensation
- DRC compliance procedures

---

### 2.6 Assembly (06_Assembly/)

#### 01_Pre_Tape_out/
- Pre-production planning

#### 02_Post_Tape_out/04_Sample_planning/
- Sample allocation and testing strategy

---

### 2.7 Tuning & CV (07_Tuning_CV/)

#### 01_Tuning_inputs/
| File | Content Focus |
|------|---------------|
| 01_Tuning_TO_strategy.pdf | Tuning methodology |
| 02_Tuning_plan_details.png | Detailed planning |
| 03_BOM_tuning_guidelines.pdf | Component selection guide |
| 04_Compliance_matrix.pdf | Requirements tracking |

#### 02_CV_preparation/
| File | Content Focus |
|------|---------------|
| 01_Tuning_flow.pdf | Process flow |
| 02_Actual_execution_plan.png | Execution timeline |
| 03_Logistic_Assembly_plan.pdf | Logistics |
| 04_EVB_socket_preparation.pdf | Test setup |
| 05_Final_delivery_schedule.pdf | Delivery planning |
| 06_Px_dB calculation method.pdf | Performance metrics |

#### 03_CV_execution/
##### 03_BOM_tracking/
- 01_Full_variants.pdf
- 02_NIJ_tuning.pdf
- 03_J01F.pdf through 07_J09_Main_Peak.pdf

##### 04_Sample_tracking/
- 01_Tuning_samples.pdf
- 02_AD2_samples.pdf

**Additional Files:**
- 01_Measurement set.pdf
- 02_Tuning tracking.pdf
- 05_Raw data_crunching.pdf

**Key Extraction Points:**
- Component value optimization
- Tuning methodology
- Sample tracking and logistics
- Performance verification

---

### 2.8 Results Analysis (08_Results_Analysis/)

#### 01_Summary.pdf
- Overall results summary

#### 02_AD2_Gate/
**Gate bias optimization studies:**
- J01M and J01I variant analysis
- iDPD vs nDPD comparison
- LUT characterization
- Sample selection criteria

#### 03_Full_Read_out/
**Complete characterization:**
- J01G, J01B, J01M variants
- Full S-parameter measurements
- Bias point optimization

#### 04_GSG_Passives_measurement/
- J06.pdf - Passive component verification

#### 05_Delta_quantification/
##### 01_Impact_of_socket_solder/
- Socket vs. soldered performance comparison
- Multiple variants (J01A, J01B, J03)

##### 02_Impact_of_mold/
- Molding compound effects

#### 06_Debug_experiments/
##### 01_Impact_of_Idq_Optimization/
- Quiescent current optimization

##### 02_Impact_of_temparature/
- Temperature dependency analysis

##### 03_Impact_of_Vds/
- Drain voltage effects

#### 07_Down_selection/
- Final variant selection

#### 08_Performance_improvement/
**Systematic optimization studies:**

| Subfolder | Focus Area | Optimization Target |
|-----------|-----------|---------------------|
| 01_ACLR_improvement | Linearity | Adjacent channel leakage ratio |
| 02_Driver_BW_improvement | Bandwidth | Driver stage BW extension |
| 03_Driver_Gain_improvement | Gain | Driver stage gain boost |
| 04_Gain_dip_correction | Frequency response | Gain flatness |
| 05_PAE_Ppeak_improvement | Efficiency | PAE and peak power |
| 06_S22_Off-state_improvement | Isolation | Output match in off-state |
| 07_Wideband_gain_flateness_improvement | Flatness | Wide-band gain profile |

#### 09_Mile-stone_comparisons/
- Progress tracking and milestone achievements

**Key Extraction Points:**
- Measurement methodology
- Performance optimization techniques
- Debug and troubleshooting approaches
- Trade-off analysis
- Final performance achievements

---

### 2.9 Simulation vs. Measurement (09_Sim_vs_Meas/)
| File | Content Focus |
|------|---------------|
| 01_PAM_B_Simulation_vs_Measurement.pdf | Model validation |

**Key Extraction Points:**
- Correlation analysis
- Model accuracy assessment
- Lessons learned for future designs

---

### 2.10 Poster (10_Poster/)
| File | Content Focus |
|------|---------------|
| 01_PAM_B_PD3_Poster.png | Conference poster presentation |

---

## 3. Cross-Project Analysis

### 3.1 Technology Flow
```
Tx_Baseline Project → Transistor Selection → PAM_B Project
(Discrete Device)                            (Integrated Module)
```

### 3.2 Shared Knowledge Domains
1. **GaN Technology**
   - Device physics
   - Thermal management
   - Reliability considerations

2. **RF Design**
   - Matching network synthesis
   - Stability analysis
   - Load-pull optimization

3. **EM Simulation**
   - 3D EM modeling
   - Parasitic extraction
   - Layout optimization

4. **Measurement**
   - Test fixture design
   - Calibration procedures
   - Data analysis

5. **Assembly**
   - Package technology
   - Material selection
   - Process control

---

## 4. Document Access Strategy

### 4.1 Priority Levels

**HIGH PRIORITY** (Read First):
1. Background/Overview documents from both projects
2. Final downselection reports
3. Results summary documents
4. Simulation vs. measurement correlation

**MEDIUM PRIORITY** (Deep Dive):
1. Design phase documentation
2. Tuning and optimization reports
3. Model development materials
4. Assembly and tapeout documents

**LOW PRIORITY** (Reference):
1. Intermediate DOE reports
2. Raw data files
3. Vendor-specific materials
4. Administrative documents

### 4.2 Reading Order for Content Extraction

**Phase 1 - Foundation:**
1. Tx_Baseline: 01_Background_overview/
2. PAM_B: 01_Overview/ and 02_Mini-pac_PAM_B/01_Introduction/

**Phase 2 - Technical Deep Dive:**
1. Tx_Baseline: 02_Design/ → 03_Measurements/ → 03_Down_selection/
2. PAM_B: 03_Design/ → 05_Tapeout/

**Phase 3 - Results & Validation:**
1. Tx_Baseline: 04_Model/ → 03_Measurements/02_Build_1_DOE1_Anteverta_Meas.pdf
2. PAM_B: 07_Tuning_CV/ → 08_Results_Analysis/ → 09_Sim_vs_Meas/

**Phase 4 - Manufacturing & Integration:**
1. Tx_Baseline: 05_Assembly/ → 06_Minipac_V02/ → 07_PCB-pac/
2. PAM_B: 06_Assembly/ → 10_Poster/

---

## 5. Data Extraction Template

For each document, extract:

```yaml
document:
  file_path: ""
  category: ""  # Theory/Design/Measurement/Analysis
  
content_extraction:
  concepts:
    - name: ""
      description: ""
      
  theoretical_analysis:
    - equations: []
    - assumptions: []
    - methodology: ""
    
  figures:
    - figure_number: ""
      caption: ""
      key_insights: ""
      
  factual_evidence:
    - measurement_data: ""
    - performance_metrics: ""
    
  trends:
    - observation: ""
    - interpretation: ""
    
  current_status:
    - achievements: []
    - limitations: []
    
  future_suggestions:
    - recommendation: ""
    - rationale: ""
    
  lessons_learned:
    - lesson: ""
    - impact: ""
    
  references:
    - citation: ""
```

---

## 6. Next Actions

### Immediate (Next Session):
- [ ] Begin extracting content from HIGH PRIORITY documents
- [ ] Create first draft of Chapter 1 (Introduction & Fundamentals)
- [ ] Populate Chapter 2 structure with Tx_Baseline data

### Short-term (Within 1 week):
- [ ] Complete extraction from all Tx_Baseline documents
- [ ] Begin PAM_B document extraction
- [ ] Create figure inventory and extraction plan

### Medium-term (Within 1 month):
- [ ] Complete all content extraction
- [ ] First draft of all 6 chapters
- [ ] Internal review and consistency check

---

## 7. Document Statistics

### Tx_Baseline Project
- **Background:** 4 documents
- **Design:** 20+ documents (10 DOE builds)
- **Measurements:** 15+ documents (10 downselection reports)
- **Model:** 7+ documents
- **Assembly:** Multiple subfolders with technical docs
- **Total:** ~50-60 primary documents

### PAM_B Project  
- **Overview:** Multiple flow charts and summaries
- **Design:** 6 major categories
- **Tapeout:** 7+ documents including EM simulations
- **Tuning/CV:** 20+ documents tracking execution
- **Results:** 50+ analysis documents
- **Total:** ~80-100 primary documents

### Combined Total: 130-160 technical documents

---

## Document Control

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-01 | Initial inventory creation | GitHub Copilot |

**Document Owner:** PA Design Reference Manual Project Team  
**Review Frequency:** Updated with each new extraction session  
**Location:** `/PA_Design_Reference_Manual/DOCUMENT_INVENTORY.md`

---

## Notes for AI Assistant

1. **File Access:** All documents are accessible via absolute paths starting with `/workspaces/Atomic_cosmic_RFView_Notes/IFX_2022_2025/02_Projects/`

2. **PDF Reading:** Use appropriate tools to extract text and figures from PDF files

3. **Priority Focus:** Start with background and overview documents to build context before diving into detailed technical content

4. **Cross-referencing:** Many documents reference each other - maintain a reference map

5. **Quality Check:** Verify extracted data against multiple sources when possible

6. **Figure Extraction:** Prioritize high-quality figures that illustrate key concepts

7. **Version Control:** Some documents have multiple versions - use the latest unless historical progression is needed

---

*End of Document Inventory*
