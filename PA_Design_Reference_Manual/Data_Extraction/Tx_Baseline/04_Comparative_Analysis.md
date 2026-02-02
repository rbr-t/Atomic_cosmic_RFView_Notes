# DOE Comparative Analysis - All Builds

**Created**: February 1, 2026  
**Status**: 🔄 Awaiting data extraction  
**Purpose**: Cross-DOE comparison tables and analysis

---

## Overview

This document consolidates performance data from all 9 DOE builds to enable:
1. Technology comparison (T-series vs R-series vs LDMOS)
2. Size scaling analysis (2.4mm to 12mm)
3. Trade-off visualization (Efficiency vs Linearity vs Power)
4. Final device selection rationale

---

## Master Comparison Table

### All DOEs Performance Summary

| DOE | Device | Size (mm) | Technology | VDS (V) | Iq (mA) | Pout (dBm) | PAE (%) | Gain (dB) | IM3 (dBc) | Rank |
|-----|--------|-----------|------------|---------|---------|------------|---------|-----------|-----------|------|
| DOE1 | T9095A | 12.00 | T-series GaN | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| DOE6 | T9095A | 12.00 | T-series GaN | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| DOE7 | T9507B | 2.40 | T-series GaN | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| DOE9 | R9505 | 11.52 | R-series GaN | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| DOE11 | T9504 | 3.84 | T-series GaN | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| DOE13 | R9505 | 6.40 | R-series GaN | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| DOE15 | T6083A | 2.28 | LDMOS | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| DOE16 | R6051A | 3.20 | R-series GaN | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| DOE17 | T9501R | 2.40 | T-series GaN | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

---

## Technology Comparison

### T-Series GaN (DOE1, DOE6, DOE7, DOE11, DOE17)
- **Devices**: T9095A, T9507B, T9504, T9501R
- **Size Range**: 2.4mm - 12mm
- **Characteristics**: TBD
- **Best Performance**: TBD

### R-Series GaN (DOE9, DOE13, DOE16)
- **Devices**: R9505, R6051A
- **Size Range**: 3.2mm - 11.52mm
- **Characteristics**: TBD
- **Best Performance**: TBD

### LDMOS (DOE15)
- **Device**: T6083A
- **Size**: 2.28mm
- **Characteristics**: TBD
- **Comparison to GaN**: TBD

---

## Size Scaling Analysis

### Performance vs Size Trends

| Size (mm) | DOE | Pout (dBm) | PAE (%) | IM3 (dBc) | Notes |
|-----------|-----|------------|---------|-----------|-------|
| 2.28 | DOE15 | TBD | TBD | TBD | LDMOS baseline |
| 2.40 | DOE7 | TBD | TBD | TBD | Small T-series |
| 2.40 | DOE17 | TBD | TBD | TBD | Latest T-series |
| 3.20 | DOE16 | TBD | TBD | TBD | Small R-series |
| 3.84 | DOE11 | TBD | TBD | TBD | Medium T-series |
| 6.40 | DOE13 | TBD | TBD | TBD | Medium-large R-series |
| 11.52 | DOE9 | TBD | TBD | TBD | Large R-series |
| 12.00 | DOE1 | TBD | TBD | TBD | Large T-series baseline |
| 12.00 | DOE6 | TBD | TBD | TBD | Large T-series chip-wire |

### Key Findings
- [ ] **Power Scaling**: TBD - Linear with size?
- [ ] **Efficiency Trend**: TBD - Optimal size?
- [ ] **Linearity vs Size**: TBD - Does size help or hurt?

---

## Trade-off Analysis

### Efficiency vs Linearity
*(Plot to be generated)*
- Best PAE: DOE# TBD @ TBD%
- Best IM3: DOE# TBD @ TBD dBc
- Best Compromise: DOE# TBD

### Power vs Size
*(Plot to be generated)*
- Most compact high-power: DOE# TBD
- Power density winner: TBD W/mm

### Cost vs Performance
- Smallest viable device: DOE# TBD
- Best value: DOE# TBD

---

## Selection Criteria Matrix

### Weighted Scoring (Example - adjust weights as needed)

| Criterion | Weight | DOE1 | DOE7 | DOE9 | DOE11 | DOE15 | DOE17 | Best |
|-----------|--------|------|------|------|-------|-------|-------|------|
| PAE | 25% | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| Pout | 20% | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| Linearity (IM3) | 20% | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| Gain | 10% | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| Size | 10% | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| Cost | 10% | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| Availability | 5% | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| **TOTAL** | **100%** | **TBD** | **TBD** | **TBD** | **TBD** | **TBD** | **TBD** | **Winner** |

---

## Final Selection

### Winner: DOE# TBD

**Device**: TBD  
**Size**: TBD mm  
**Technology**: TBD

**Rationale**:
- [ ] TBD: Why this device was selected
- [ ] Performance advantages
- [ ] Trade-off justification
- [ ] Integration considerations for PAM_B

**Runner-up**: DOE# TBD  
**Reason for not selecting**: TBD

---

## Plots to Generate

Using `plot_tradeoffs.R` script:

1. **Size vs Pout** - Power scaling trend
2. **Size vs PAE** - Efficiency sweet spot
3. **PAE vs IM3** - Efficiency-linearity trade-off
4. **Pout vs IM3** - Power-linearity trade-off
5. **Technology Comparison** - T vs R vs LDMOS radar chart
6. **3D Surface** - Interactive Pout × PAE × IM3

---

## Integration with Chapter 1

### Section 1.4.4: DOE Results Summary
- Use master comparison table
- Include technology comparison insights
- Show size scaling trends

### Section 1.4.5: Final Selection
- Present selection criteria matrix
- Show winning design characteristics
- Justify downselection decision

### Figures for Chapter 1
- Figure 1.4.1: DOE comparison bar chart
- Figure 1.4.2: Technology comparison radar
- Figure 1.4.3: Size scaling plots
- Figure 1.4.4: Trade-off scatter plots

---

**Status**: 🔄 Template ready, awaiting DOE data extraction  
**Next Action**: Populate after completing individual DOE extractions  
**Last Updated**: February 1, 2026

