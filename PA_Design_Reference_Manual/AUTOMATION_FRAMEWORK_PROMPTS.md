# PA Design Automation Framework - Prompt Structure

## Enhanced for Linearity, Trade-offs, and Mass Manufacturing

---

## 1. CORE DESIGN PARAMETERS

### 1.1 Performance Specifications
```yaml
primary_specs:
  frequency:
    center_freq: [value] MHz/GHz
    bandwidth: [value] MHz
    operating_range: [min, max] MHz
  
  output_power:
    target_pout: [value] dBm
    p1db: [value] dBm
    psat: [value] dBm
    power_flatness: ±[value] dB across band
  
  efficiency:
    pae_target: [value] %
    pae_at_backoff: [value] % @ [X] dB backoff
    drain_efficiency: [value] %
    
  linearity:  # CRITICAL SPECIFICATION
    im3_spec: [value] dBc @ [tone_spacing] MHz
    acpr: [value] dBc @ [offset] MHz
    evm: [value] % (for modulated signals)
    dpd_capability: required/optional
    linearity_backoff: [X] dB from P1dB for linear operation
    
  gain:
    small_signal_gain: [value] dB
    gain_flatness: ±[value] dB across band
    
  stability:
    k_factor: > 1 (unconditionally stable)
    load_vswr_tolerance: [value]:1
```

### 1.2 Mass Manufacturing Considerations
```yaml
manufacturing:
  yield_targets:
    electrical_yield: > [95]%
    assembly_yield: > [98]%
    overall_yield: > [93]%
  
  process_capability:
    cpk_target: > 1.33
    critical_parameters:
      - output_power: ±[0.5] dB
      - efficiency: ±[2] %
      - gain: ±[0.3] dB
      - linearity: ±[1] dB (IM3)
  
  cost_targets:
    target_unit_cost: $[X] @ [Y]k volume
    test_time: < [Z] seconds per unit
    assembly_complexity: [low/medium/high]
  
  reliability:
    mtbf: > [X] hours
    operating_temp_range: [-40, +85] °C
    storage_temp_range: [-55, +125] °C
    thermal_cycles: [X] cycles
    
  supply_chain:
    component_sources: [multiple/single]
    lead_time: < [X] weeks
    obsolescence_risk: [low/medium/high]
```

---

## 2. LINEARITY-FOCUSED DESIGN PROMPTS

### 2.1 Linearity Analysis Prompt
```
TASK: Analyze and optimize PA linearity performance

INPUTS:
- Transistor model: [model_file]
- Bias point: Class [A/AB/B] @ IQ = [X] mA
- Input power sweep: [Pmin] to [Pmax] dBm
- Modulation: [CW / OFDM / 5G NR / Custom]

REQUIRED ANALYSES:
1. Two-Tone IM3 Characterization:
   - Tone spacing: [1, 5, 10] MHz
   - Power sweep from linear to compression
   - Extract: IM3 vs Pout, OIP3, sweet spot
   
2. ACPR Analysis (if applicable):
   - Standard: [3GPP / IEEE / Custom]
   - Channels: Adjacent, Alternate
   - vs. Output power and frequency
   
3. AM-AM / AM-PM Distortion:
   - Gain compression characteristics
   - Phase distortion vs. amplitude
   - Memory effects assessment
   
4. Modulated Signal Performance:
   - EVM vs output power
   - Constellation diagram analysis
   - Spectral regrowth measurement

OUTPUT REQUIREMENTS:
✓ Linearity plots:
  - IM3 (dBc) vs Pout (dBm) 
  - ACPR vs Pout
  - AM-AM and AM-PM curves
  - EVM vs Pout
  
✓ Linearity metrics table:
  | Metric | @ Linear Point | @ P1dB | @ Psat |
  |--------|----------------|--------|--------|
  | Pout   |                |        |        |
  | IM3    |                |        |        |
  | ACPR   |                |        |        |
  | EVM    |                |        |        |
  
✓ DPD feasibility assessment:
  - Pre-DPD linearity
  - Required DPD order
  - Post-DPD performance estimate
```

### 2.2 Bias Point Trade-off Prompt
```
TASK: Optimize bias point for linearity vs. efficiency trade-off

ANALYSIS MATRIX:
For each bias class [A, AB (IQ=[X1, X2, X3] mA), B]:

1. DC Operating Point:
   - Quiescent current
   - Quiescent power
   - Thermal dissipation
   
2. Performance Metrics:
   - Gain and P1dB
   - PAE (average and at backoff)
   - IM3 and ACPR
   - EVM (if modulated)
   
3. Trade-off Plots (REQUIRED):
   ┌─────────────────────────────────────┐
   │ Plot 1: PAE vs IM3                  │
   │ - X-axis: IM3 (dBc)                 │
   │ - Y-axis: PAE (%)                   │
   │ - Each point = different bias       │
   │ - Pareto frontier highlighted       │
   └─────────────────────────────────────┘
   
   ┌─────────────────────────────────────┐
   │ Plot 2: Pout vs Linearity           │
   │ - X-axis: Pout (dBm)                │
   │ - Y-axis: IM3 (dBc)                 │
   │ - Color: Different bias classes     │
   │ - Spec line overlay                 │
   └─────────────────────────────────────┘
   
   ┌─────────────────────────────────────┐
   │ Plot 3: Efficiency vs Backoff       │
   │ - X-axis: Backoff (dB)              │
   │ - Y-axis: PAE (%)                   │
   │ - Multiple curves: bias classes     │
   │ - Operating point marked            │
   └─────────────────────────────────────┘

RECOMMENDATION FORMAT:
✓ Optimal bias point: Class [X] @ IQ = [Y] mA
✓ Justification:
  - Meets linearity: IM3 = [X] dBc (spec: [Y] dBc) ✓
  - Achieves efficiency: PAE = [A] % (target: [B] %) ✓
  - Margin to spec: [C] dB
✓ Trade-offs made:
  - Sacrifice [X]% PAE for [Y] dB better IM3
  - Compromise: [explanation]
```

---

## 3. TRADE-OFF ANALYSIS FRAMEWORK

### 3.1 Multi-Dimensional Trade-off Plots

**Plot Type 1: Performance Triangle**
```
     Efficiency (PAE)
           △
          /│\
         / │ \
        /  │  \
       /   │   \
      /    ●    \     ● = Operating Point
     /     │     \    ▲ = Specification Limit
    /      │      \   ★ = Optimal Design
   /       │       \
  ▲────────┼────────▲
Linearity (IM3)  Output Power

Purpose: Visualize 3-way trade-off
Action: Move operating point toward sweet spot
```

**Plot Type 2: Pareto Front Analysis**
```
TASK: Generate Pareto-optimal designs

PROCEDURE:
1. Define design space:
   - Transistor size: [W_min, W_max]
   - Bias current: [IQ_min, IQ_max]
   - Load impedance: [Z_min, Z_max]
   - Input power: [Pin_min, Pin_max]

2. Sweep and evaluate:
   - Run [N=1000] combinations
   - Calculate all metrics for each
   - Identify non-dominated solutions

3. Generate Pareto plots:
   
   Plot: PAE vs IM3 Pareto Front
   ┌─────────────────────────────────────┐
   │ 60%┤         ★                      │
   │    │       ★   ★                    │
   │ PAE│     ★       ★                  │
   │ 40%┤   ★           ★                │
   │    │ ★               ★              │
   │ 20%┤                   ★            │
   │    └──────────────────────────────  │
   │      -50  -45  -40  -35  -30 dBc   │
   │            IM3 Level                │
   │                                     │
   │ Legend:                             │
   │ ★ = Pareto optimal designs          │
   │ ● = Sub-optimal designs (hidden)    │
   │ ◆ = Selected design point           │
   │ ▬ = Specification limit             │
   └─────────────────────────────────────┘

4. Recommendation:
   - Present top 3-5 Pareto-optimal designs
   - Highlight trade-offs for each
   - Suggest design based on priority weights
```

**Plot Type 3: Design Space Exploration**
```
Contour Plot: PAE vs (IQ, ZL)

         Load Impedance (Ω)
         ↑
    100 │    [45]  [50]  [52]  [50]  [45]
         │
     80 │    [48]  [55]  [58]  [55]  [48]
         │
ZL   60 │    [50]  [58]  [62]★ [58]  [50]
         │
     40 │    [48]  [55]  [58]  [55]  [48]
         │
     20 │    [45]  [50]  [52]  [50]  [45]
         └─────────────────────────────────→
            10   20   30   40   50  IQ (mA)

★ = Optimal point: IQ=30mA, ZL=60Ω → PAE=62%

ACTION: Plot similar contours for IM3, Pout, Gain
OVERLAY: All constraints and find feasible region
```

### 3.2 Manufacturing Trade-off Analysis

**Plot Type 4: Yield vs Performance**
```
TASK: Balance performance targets with manufacturing yield

ANALYSIS:
1. Monte Carlo simulation:
   - Component tolerance: [±X]%
   - Process variation: [±Y]%
   - Temperature variation: [-40, +85]°C
   - N_samples = [10,000]

2. Generate yield curves:
   
   Plot: Yield vs Performance Margin
   ┌─────────────────────────────────────┐
   │100%┤─────────★                      │
   │    │         ↓ Design Point         │
   │    │       ╱                        │
   │Yield 80%┤     ╱                     │
   │    │   ╱                            │
   │ 60%┤ ╱                              │
   │    ╱                                │
   │    └──────────────────────────────  │
   │     0dB  1dB  2dB  3dB  4dB  5dB    │
   │     Performance Margin to Spec      │
   │                                     │
   │ Analysis:                           │
   │ • At ★ design: 95% yield           │
   │ • Cost: Overdesign by 2dB           │
   │ • Trade-off: Accept 85% yield →    │
   │   Save $X per unit                  │
   └─────────────────────────────────────┘

3. Cost-Yield-Performance 3D Plot:
   
            Yield (%)
              ↑
           100│     ╱★╲
              │   ╱     ╲
              │ ╱         ╲
            80├╱           ╲
              │              ╲
              └────────────────→ Cost ($)
             ╱                    
           ╱                      
         ╱                        
    Performance                   
    
    ★ = Optimal operating point
    
4. RECOMMENDATION:
   ✓ Design margin: [X] dB above spec
   ✓ Expected yield: [Y] %
   ✓ Unit cost: $[Z]
   ✓ Justification: [Balance statement]
```

---

## 4. MANUFACTURING-CENTRIC DESIGN PROMPTS

### 4.1 Design for Manufacturing (DFM)

```
TASK: Evaluate and optimize design for mass manufacturing

CHECKLIST ANALYSIS:

1. Component Selection:
   ✓ Multi-source components: [%]
   ✓ Obsolescence risk: [Low/Med/High]
   ✓ Cost vs volume:
     - @ 1k: $[X]
     - @ 10k: $[Y]
     - @ 100k: $[Z]

2. Assembly Complexity:
   ✓ Total component count: [N]
   ✓ Fine-pitch components: [N] (risk: [H/M/L])
   ✓ Manual assembly steps: [N]
   ✓ Automated assembly: [%]
   ✓ Assembly time: [X] minutes
   
3. Test Strategy:
   ✓ Test points accessible: [Y/N]
   ✓ Test time per unit: [X] seconds
   ✓ Test coverage: [%]
   ✓ Automated test: [Y/N]
   
4. Tuning Requirements:
   ✓ Tuning elements: [N]
   ✓ Tuning time: [X] minutes
   ✓ Skill level required: [Low/Med/High]
   ✓ Tuning-free design: [Y/N]
   
5. Thermal Management:
   ✓ Heatsink required: [Y/N]
   ✓ Thermal interface material: [Type]
   ✓ Assembly thermal stress: [Low/Med/High]

TRADE-OFF: Tuning vs Yield
┌─────────────────────────────────────┐
│        Design Approach              │
│                                     │
│ A. Tuning-Required Design:          │
│    • Lower initial cost             │
│    • Higher assembly time           │
│    • Skilled labor needed           │
│    • 95%+ yield achievable          │
│                                     │
│ B. Tuning-Free Design:              │
│    • Higher component cost          │
│    • Faster assembly                │
│    • Unskilled labor OK             │
│    • 85-90% yield typical           │
│                                     │
│ RECOMMENDATION: [A/B]               │
│ Justification:                      │
│ - Volume: [X] units/year            │
│ - Labor cost: $[Y]/hour             │
│ - Break-even: [Z] units             │
│ - Total cost impact: [±W]%          │
└─────────────────────────────────────┘
```

### 4.2 Process Capability Analysis

```
TASK: Ensure design meets manufacturing process capabilities

ANALYSIS FOR EACH CRITICAL PARAMETER:

Parameter: Output Power (Pout)
┌─────────────────────────────────────┐
│ Specification: 40 ± 0.5 dBm         │
│                                     │
│ Statistical Distribution:           │
│         │                           │
│    LSL  │  μ    │  USL              │
│     │   │   │   │   │               │
│  39.5  │  40.2 │  40.5 dBm         │
│     │   ▼   │   │   │               │
│     │   ╱█╲ │   │   │               │
│     │ ╱███╲│   │   │               │
│     │╱█████╲   │   │               │
│     ┴───────┴───┴───┴              │
│                                     │
│ Cp  = 1.45  (Process spread)        │
│ Cpk = 1.28  (Process centering)     │
│                                     │
│ Status: ✓ Capable (Cpk > 1.33)     │
│                                     │
│ Predicted yield: 99.7%              │
│ Defect rate: 3,000 ppm              │
│                                     │
│ ACTIONS:                            │
│ • Process centered: OK              │
│ • Specification window: Adequate    │
│ • Recommendation: No action needed  │
└─────────────────────────────────────┘

REPEAT FOR: PAE, Gain, IM3, ACPR, etc.

SUMMARY TABLE:
┌──────────┬─────┬─────┬────────┬────────┐
│Parameter │ Cp  │ Cpk │ Yield  │ Action │
├──────────┼─────┼─────┼────────┼────────┤
│ Pout     │1.45 │1.28 │ 99.7%  │   ✓    │
│ PAE      │1.12 │0.95 │ 95.2%  │   ⚠    │
│ Gain     │1.67 │1.52 │ 99.9%  │   ✓    │
│ IM3      │1.21 │1.08 │ 97.8%  │   ⚠    │
└──────────┴─────┴─────┴────────┴────────┘

⚠ = Requires design margin increase or
     tighter component tolerance
```

---

## 5. COMPLETE AUTOMATION PROMPT TEMPLATE

### 5.1 Initial Design Generation (Template Phase)

```yaml
PROJECT: [PA_Design_Name]
AUTOMATION_LEVEL: TEMPLATE

# === SPECIFICATIONS ===
specs:
  frequency: [X] GHz
  output_power: [Y] dBm
  pae: [Z] %
  linearity:
    im3_target: -[A] dBc
    backoff_power: [B] dB from P1dB
  manufacturing:
    target_yield: [C] %
    cost_target: $[D] per unit

# === CONSTRAINTS ===
constraints:
  transistor: [model_name]
  supply_voltage: [VDD] V
  bias_class: [A/AB/B/C]
  technology: [GaN/GaAs/LDMOS]
  
# === TRADE-OFF PRIORITIES ===
priorities:
  linearity: [1-10]
  efficiency: [1-10]
  cost: [1-10]
  yield: [1-10]
  
# === AUTOMATION REQUEST ===
generate:
  - initial_design: YES
  - trade_off_plots: 
      - pae_vs_im3
      - pout_vs_linearity
      - yield_vs_margin
      - cost_vs_performance
  - manufacturing_analysis: YES
  - recommendations: TOP_3_DESIGNS
```

### 5.2 Guided Optimization (Guided Phase)

```yaml
PROJECT: [PA_Design_Name]
AUTOMATION_LEVEL: GUIDED

# === CURRENT DESIGN STATUS ===
current_performance:
  pout: [X] dBm (target: [Y] dBm)
  pae: [A] % (target: [B] %)
  im3: -[C] dBc (target: -[D] dBc)  ← PRIORITY
  
# === OPTIMIZATION GOALS ===
optimize:
  primary: IMPROVE_LINEARITY
  target_improvement: [E] dB in IM3
  constraints:
    - maintain_pae: ">= [F]%"
    - maintain_pout: ">= [G] dBm"
    - max_cost_increase: "[H]%"
    - maintain_yield: ">= [I]%"

# === DESIGN VARIABLES ===
variables:
  bias_point:
    current_iq: [J] mA
    range: [K to L] mA
    
  load_impedance:
    current_zl: [M] Ω
    range: [N to O] Ω
    
  input_match:
    optimize: YES
    metric: IM3
    
# === EXPLORATION STRATEGY ===
strategy:
  method: DOE  # Design of Experiments
  samples: [P]
  algorithm: PARETO_OPTIMIZATION
  
# === REQUIRED OUTPUTS ===
outputs:
  - sensitivity_analysis
  - pareto_front
  - trade_off_plots:
      - im3_vs_bias_sweep
      - im3_vs_load_impedance
      - efficiency_vs_linearity
  - top_N_candidates: [Q]
  - manufacturing_impact_analysis
```

### 5.3 Autonomous Design (Autonomous Phase)

```yaml
PROJECT: [PA_Design_Name]
AUTOMATION_LEVEL: AUTONOMOUS

# === HIGH-LEVEL REQUIREMENTS ===
requirements:
  application: [5G_Base_Station/Radar/Satellite]
  frequency_band: [X-Y] GHz
  output_power: [Z] dBm
  efficiency_priority: [HIGH/MEDIUM/LOW]
  linearity_priority: [HIGH/MEDIUM/LOW]
  cost_priority: [HIGH/MEDIUM/LOW]
  
# === MANUFACTURING CONTEXT ===
manufacturing_context:
  annual_volume: [N] units
  target_cost: $[X] per unit
  yield_requirement: >[Y]%
  assembly_capability: [AUTOMATED/MANUAL/MIXED]
  test_capability: [FULL/PARTIAL/BASIC]

# === AI AGENT INSTRUCTIONS ===
agent_tasks:
  1. technology_selection:
     - evaluate: [GaN, GaAs, LDMOS, SiGe]
     - criteria: [freq, power, efficiency, cost, linearity]
     - output: technology_recommendation + rationale
     
  2. topology_selection:
     - options: [single_stage, two_stage, three_stage]
     - optimize_for: [linearity, efficiency, gain]
     - output: architecture_with_tradeoffs
     
  3. transistor_selection:
     - create_shortlist: TOP_5
     - simulate_each: YES
     - compare: [datasheet_table, performance_plots]
     - output: selected_transistor + justification
     
  4. bias_and_matching:
     - explore_bias_space: [A, AB, B classes]
     - optimize_matching: [im3_focused]
     - generate_tradeoff_plots: YES
     - output: optimal_bias + matching_networks
     
  5. manufacturing_optimization:
     - analyze_tolerances: YES
     - predict_yield: MONTE_CARLO_10K
     - cost_analysis: DETAILED
     - output: dfm_recommendations + yield_curves
     
  6. validation:
     - corner_analysis: [TT, SS, FF, FS, SF]
     - temp_sweep: [-40, +25, +85]°C
     - linearity_sweep: FULL_POWER_RANGE
     - output: validation_report + margin_analysis

# === SUCCESS CRITERIA ===
success_metrics:
  linearity: im3 < -[A] dBc (CRITICAL)
  efficiency: pae > [B]%
  yield: > [C]%
  cost: < $[D] per unit
  margin_to_spec: > [E] dB
  
# === DELIVERABLES ===
deliverables:
  - complete_schematic
  - layout_guidelines
  - bom_with_alternates
  - performance_report:
      - all_spec_compliance
      - trade_off_plots
      - manufacturing_analysis
      - cost_breakdown
  - test_plan
  - tuning_procedure (if needed)
```

---

## 6. LINEARITY-SPECIFIC OPTIMIZATION ALGORITHMS

### 6.1 Sweet Spot Finder
```python
"""
Algorithm: Find optimal operating point for best linearity
"""

def find_linearity_sweet_spot(transistor_model, freq, vdd):
    """
    Sweep bias and load impedance to find IM3 sweet spot
    
    Returns: optimal_iq, optimal_zl, performance_metrics
    """
    
    # Define search space
    iq_range = np.linspace(10, 100, 50)  # mA
    zl_range = np.linspace(20, 100, 50)  # Ohms
    
    results = []
    
    for iq in iq_range:
        for zl in zl_range:
            # Simulate two-tone test
            pout, pae, im3, gain = simulate_two_tone(
                model=transistor_model,
                bias_iq=iq,
                load_z=zl,
                freq=freq,
                vdd=vdd
            )
            
            results.append({
                'iq': iq,
                'zl': zl,
                'pout': pout,
                'pae': pae,
                'im3': im3,
                'gain': gain,
                'fom': calculate_fom(pout, pae, im3)  # Figure of Merit
            })
    
    # Find Pareto-optimal points
    pareto_points = find_pareto_front(results, 
                                       objectives=['im3', 'pae'])
    
    # Select best based on priorities
    optimal = select_by_priority(pareto_points, 
                                  priority_weights)
    
    # Generate trade-off plots
    plot_im3_vs_bias(results)
    plot_efficiency_vs_linearity(results)
    plot_contour_map(results, param='im3')
    
    return optimal
```

### 6.2 Multi-Objective Optimization
```python
"""
Genetic Algorithm for PA Design Optimization
Objectives: Maximize PAE, Minimize IM3, Maximize Pout, Minimize Cost
"""

def optimize_pa_design(specs, constraints, manufacturing_params):
    """
    Multi-objective GA optimization
    """
    
    # Define chromosome (design variables)
    chromosome = {
        'transistor_width': [50, 500],  # μm
        'bias_iq': [10, 80],  # mA
        'load_z_real': [20, 100],  # Ohms
        'load_z_imag': [-20, 20],  # Ohms
        'harmonic_tuning': [0, 1],  # Binary: yes/no
    }
    
    # Define fitness function
    def fitness(individual):
        pout, pae, im3, cost = simulate_design(individual)
        
        # Penalty for not meeting specs
        penalty = 0
        if im3 > specs['im3_max']:
            penalty += 1000 * (im3 - specs['im3_max'])
        if pout < specs['pout_min']:
            penalty += 1000 * (specs['pout_min'] - pout)
        if pae < specs['pae_min']:
            penalty += 500 * (specs['pae_min'] - pae)
            
        # Multi-objective score
        score = (
            w1 * normalize(pae, 0, 80) +
            w2 * normalize(-im3, -60, -30) +
            w3 * normalize(pout, 30, 50) +
            w4 * normalize(-cost, -100, 0)
        ) - penalty
        
        return score
    
    # Run GA
    population = initialize_population(n=100)
    
    for generation in range(500):
        # Evaluate fitness
        fitness_scores = [fitness(ind) for ind in population]
        
        # Selection
        parents = tournament_selection(population, fitness_scores)
        
        # Crossover
        offspring = crossover(parents)
        
        # Mutation
        offspring = mutate(offspring, mutation_rate=0.1)
        
        # Next generation
        population = select_next_generation(population + offspring)
        
        # Track Pareto front
        if generation % 10 == 0:
            update_pareto_front(population)
    
    # Return Pareto-optimal designs
    return get_pareto_front(), plot_pareto_fronts()
```

---

## 7. MANUFACTURING DECISION SUPPORT

### 7.1 Cost-Performance-Yield Optimizer

```
DECISION TREE: Tuning vs Tuning-Free Design

Volume: [X] units/year
┌─────────────────────────────────────────┐
│                                         │
│      Volume < 10k/year?                 │
│            │                            │
│         YES│                   NO       │
│            ↓                    ↓       │
│    ┌──────────────┐    ┌──────────────┐│
│    │ Tuning-Based │    │ Tuning-Free  ││
│    │   Design     │    │   Design     ││
│    │              │    │              ││
│    │ • Lower BOM  │    │ • Higher BOM ││
│    │ • Higher     │    │ • Lower      ││
│    │   Assembly   │    │   Assembly   ││
│    │ • Skilled    │    │ • Unskilled  ││
│    │   Labor      │    │   Labor      ││
│    │ • 95%+ Yield │    │ • 85% Yield  ││
│    │              │    │              ││
│    │ Total Cost:  │    │ Total Cost:  ││
│    │ $[Y]/unit    │    │ $[Z]/unit    ││
│    └──────────────┘    └──────────────┘│
│                                         │
│ RECOMMENDATION: [Tuning/Tuning-Free]    │
│ Break-even volume: [N] units/year       │
│                                         │
│ Sensitivity Analysis:                   │
│ • Labor cost ±20%: [Impact]            │
│ • Component cost ±10%: [Impact]         │
│ • Yield ±5%: [Impact]                   │
└─────────────────────────────────────────┘
```

### 7.2 Reliability Prediction

```
THERMAL DERATING AND RELIABILITY

Operating Conditions:
- Ambient: [Ta] °C
- Junction: [Tj] °C
- Dissipation: [Pd] W

Reliability Analysis:
┌─────────────────────────────────────┐
│ Arrhenius Model: MTBF vs Tj         │
│                                     │
│ MTBF (hours)                        │
│   ↑                                 │
│1M │ ●                               │
│   │   ╲                             │
│500k│     ●                           │
│   │       ╲                         │
│100k│         ●                       │
│   │           ╲                     │
│ 50k│             ●       ★          │
│   │               ╲                 │
│ 10k│                 ●               │
│   └─────────────────────────────→  │
│    100  120  140  160  180  200    │
│          Junction Temp (°C)         │
│                                     │
│ ★ = Current design: Tj=150°C        │
│     MTBF = 80,000 hours             │
│                                     │
│ RECOMMENDATION:                     │
│ • Add thermal margin: 10°C          │
│ • Improve heatsinking               │
│ • New MTBF: 120,000 hours          │
│ • Reliability improvement: 50%      │
└─────────────────────────────────────┘
```

---

## 8. COMPLETE DESIGN REPORT TEMPLATE

### 8.1 Automated Report Structure

```markdown
# PA Design Report: [Project_Name]
## Linearity-Optimized with Manufacturing Analysis

---

## 1. Executive Summary
- Design met all specifications: [✓/✗]
- Linearity margin: [X] dB
- Manufacturing yield: [Y]%
- Unit cost: $[Z]
- Recommendation: [APPROVE/REVISE]

---

## 2. Performance Summary

### 2.1 Key Metrics
| Metric | Spec | Achieved | Margin |
|--------|------|----------|--------|
| Pout | [X] dBm | [Y] dBm | +[Z] dB |
| PAE | [A]% | [B]% | +[C]% |
| IM3 | <-[D] dBc | -[E] dBc | +[F] dB |
| ACPR | <-[G] dBc | -[H] dBc | +[I] dB |
| Gain | [J] dB | [K] dB | +[L] dB |

### 2.2 Linearity Performance
- **Two-Tone IM3:**
  [Plot: IM3 vs Pout]
  - Linear region: [X] to [Y] dBm
  - Sweet spot: [Z] dBm output
  - OIP3: [A] dBm

- **AM-AM / AM-PM:**
  [Plot: Gain & Phase vs Pin]
  - Gain compression: [B] dB @ P1dB
  - Phase distortion: [C]° @ P1dB

- **ACPR (if applicable):**
  [Plot: ACPR vs Pout]
  - Compliant up to: [D] dBm

---

## 3. Trade-off Analysis

### 3.1 Performance Triangle
[Insert: Efficiency-Linearity-Power triangle plot]
- Operating point: ★
- Spec boundaries: ▬
- Pareto front: ●●●

### 3.2 Bias Optimization
[Insert: PAE vs IM3 trade-off plot]
- Selected bias: Class [X] @ [Y] mA
- Justification: Best trade-off between linearity and efficiency
- Alternative options: [List with pros/cons]

### 3.3 Design Space Exploration
[Insert: Contour plots for IM3, PAE vs design variables]
- Optimal region identified
- Sensitivity analysis complete
- Robustness confirmed

---

## 4. Manufacturing Analysis

### 4.1 Yield Prediction
[Insert: Monte Carlo yield histogram]
- Expected yield: [X]%
- Defect rate: [Y] ppm
- Cpk for critical parameters: [Table]

### 4.2 Cost Analysis
| Item | Cost @ 1k | Cost @ 10k | Cost @ 100k |
|------|-----------|------------|-------------|
| Components | $[A] | $[B] | $[C] |
| Assembly | $[D] | $[E] | $[F] |
| Test | $[G] | $[H] | $[I] |
| **Total** | **$[J]** | **$[K]** | **$[L]** |

### 4.3 DFM Assessment
- Assembly complexity: [Low/Med/High]
- Tuning required: [Yes/No]
- Test time: [X] seconds
- Critical tolerances: [List]

---

## 5. Recommendations

### 5.1 Design Approval
✓ Design APPROVED for production
  - All specs met with margin
  - Manufacturing feasible
  - Cost target achieved

### 5.2 Risk Mitigation
⚠ Monitor these parameters:
  - [Parameter 1]: Margin is [X] dB (recommend monitoring)
  - [Parameter 2]: Process sensitivity requires [action]

### 5.3 Next Steps
1. Prototype build: [N] units
2. Characterization: Full linearity sweep
3. Reliability testing: [X] hours
4. Manufacturing ramp: [Plan]

---

**Report Generated:** [Date]
**Automation Level:** [Template/Guided/Autonomous]
**Engineer:** [Name]
**Approved By:** [Name]
```

---

## 9. SUMMARY OF ENHANCEMENTS

### Added Focus Areas:

1. **Linearity Priority:**
   - ✅ IM3, ACPR, EVM as critical specs
   - ✅ Two-tone and modulated signal analysis
   - ✅ AM-AM / AM-PM characterization
   - ✅ DPD capability assessment
   - ✅ Linearity-focused optimization algorithms

2. **Trade-off Plots:**
   - ✅ PAE vs IM3 (Pareto front)
   - ✅ Pout vs Linearity
   - ✅ Efficiency vs Backoff
   - ✅ Performance triangle visualization
   - ✅ Design space contour plots
   - ✅ Yield vs Performance margin

3. **Manufacturing Perspective:**
   - ✅ Yield prediction and Cpk analysis
   - ✅ Cost vs volume analysis
   - ✅ Tuning vs tuning-free trade-offs
   - ✅ DFM checklists
   - ✅ Assembly complexity assessment
   - ✅ Reliability and MTBF analysis
   - ✅ Supply chain considerations

### Design Decision Support:
- Multi-dimensional trade-off visualization
- Pareto-optimal design identification
- Manufacturing-cost-performance balance
- Automated recommendation generation

---

**Document Version:** 2.0  
**Last Updated:** February 1, 2026  
**Status:** Enhanced with linearity, trade-offs, and manufacturing focus
