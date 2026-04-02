# Implementation Roadmap

**Status**: Rubix M1 (Q2 2026) — Transistor Design Level Complete

---

## Phase Summary

| Phase | Milestone | Status | Completion |
|---|---|---|---|
| **Phase 1** | Spec-Driven Design (System → Stage) | ✅ Complete | 100% |
| **Phase 2** | Lineup Calculator (Physics 4.2) | ✅ Complete | 100% |
| **Phase 3** | Transistor Design Level (Stage → Device) | 🚧 In Progress | 70% |
| **Phase 4** | AI Agent Mesh (7 Specialist Agents) | 🚧 In Progress | 15% |
| **Phase 5** | Production Hardening | 🚧 In Progress | 60% |
| **Phase 6** | MCP Simulation Bridge (ADS/AWR) | ⏸️ Pending | 0% |

---

## Current Sprint (Rubix M1 — Transistor Design)

### Completed ✅
- [x] Ropt formula corrected for GaN/SiC (Vknee accounting)
- [x] Doherty PAE backoff topology-aware
- [x] Topology display UI (main/peak stages in parallel)
- [x] Gate width calculation engine
- [x] L-match synthesis (Q-factor method)
- [x] Transistor design server module
- [x] Spec compliance validation panel

### In Progress 🚧
- [ ] 3+ stage support (currently 2-stage Doherty only)
- [ ] Auto-fix recommendations when spec fails AMBER/RED
- [ ] Architecture-agent topology re-evaluation listener
- [ ] Theory-agent formula delegation (DRY)

### Blockers
- **Unit tests**: No tests exist for `calc_transistor_sizing.R` (CRITICAL)
- **Theory agent**: Stub LLM calls; needs real GPT-4 integration
- **MCP integration**: Disabled; requires ADS tool availability verification

---

## Phase 4 Roadmap — AI Agent Mesh (7 Agents → 1 Strategy Orchestrator)

### Priority 1: Foundation Agents (Weeks 1-4)

#### 1.1 Theory Agent ✅
**Status**: Complete (203 lines, fully functional)

**What it does**:
- Physics questions answered from knowledge base + LLM
- Device recommendations based on specs
- Fallback to demo data without API key

**Location**: `src/plugins/rf_pa_design/agents/theory_agent.R`

**Next**: Delegate formula calls from `calc_transistor_sizing.R` to avoid duplication

---

#### 1.2 Architecture Agent 🚧 **NEXT TARGET**
**Status**: Stub + `.agent.md` influence section

**What it needs to do**:
- Select topology based on specs (Doherty, balanced, push-pull, Chireix)
- Respond to `topology_recheck_needed` event from transistor module
- Suggest component adjustments (e.g., "Ropt < 5Ω → use Doherty main/peak")
- Rate topology match (% confidence)

**Implementation sketch**:
```r
ArchitectureAgent <- R6::R6Class("ArchitectureAgent", inherit = BaseAgent, public = list(
  execute = function(spec_data) {
    # 1. Extract specs
    pout <- spec_data$power_out
    freq <- spec_data$frequency
    pae_target <- spec_data$pae_target

    # 2. Call LLM (or lookup table for demo)
    candidate_topologies <- private$rank_topologies(list(
      doherty = list(pae_gain = 15, complexity = "high"),
      balanced = list(pae_gain = 5, complexity = "low"),
      push_pull = list(pae_gain = 3, complexity = "medium")
    ), pae_target)

    # 3. Return recommendation
    return(list(
      recommended_topology = candidate_topologies[[1]]$name,
      alternatives = candidate_topologies[2:3],
      confidence = 0.85,
      reasoning = "Doherty selected for 15 dB PAE backoff"
    ))
  }
))
```

**Timeline**: 1 week (reference theory_agent.R pattern)

---

#### 1.3 Simulation Agent 🚧
**Status**: Stub — needs MCP bridge

**What it needs to do**:
- Accept circuit netlist + specs
- Call ADS/AWR via MCP
- Parse S-parameter results
- Return gain, PAE, stability metrics

**Implementation sketch**:
```r
SimulationAgent <- R6::R6Class("SimulationAgent", inherit = BaseAgent, public = list(
  execute = function(netlist, simulation_params) {
    # 1. Format netlist for ADS
    formatted_netlist <- private$format_for_ads(netlist)

    # 2. Call MCP tool
    sim_result <- private$call_mcp("ads_run_simulation", list(
      netlist = formatted_netlist,
      frequency = simulation_params$frequency,
      power = simulation_params$power
    ))

    # 3. Parse results
    parsed <- private$parse_s_params(sim_result$sparams)

    return(list(
      gain_db = parsed$s21_db,
      pae = parsed$pae,
      stability = parsed$k_factor,
      sparams = parsed
    ))
  }
))
```

**Dependency**: MCP integration enabled in `config/app_config.yaml`

**Timeline**: 2 weeks (requires tool access verification)

---

### Priority 2: Output Agents (Weeks 5-8)

#### 2.1 Layout Agent
- PCB routing constraints
- Via placement for current flow
- Substrate EM simulation flags

#### 2.2 Measurement Agent
- Lab equipment gateway interface
- Touchstone data import
- Calibration procedures

#### 2.3 Debug Agent
- Sim vs. measurement anomaly detection
- Root cause suggestions (match mismatch, parasitic coupling, etc.)

---

### Priority 3: Strategy Agent (Week 9 — Integration)
- Orchestrates all 6 agents in sequence
- Manages state transitions
- Generates design report with audit trail

---

## Phase 5 — Production Hardening

### Security
- [ ] Enable `auth_enabled: true` + RBAC
- [ ] Set API keys via environment variables
- [ ] Database connection SSL/TLS
- [ ] Session encryption

### Performance
- [ ] Profile large LP file batches (~1000 points)
- [ ] Implement database query caching
- [ ] Optimize JavaScript canvas rendering
- [ ] Add distributed tracing (optional)

### Reliability
- [ ] Circuit breaker pattern for MCP calls
- [ ] Dead letter queue for failed jobs
- [ ] Database backup & restore procedures
- [ ] Monitoring alerts (CPU, memory, DB connections)

**Timeline**: 3-4 weeks

---

## Phase 6 — MCP Simulation Bridge

### Prerequisites
1. Verify ADS/AWR tool access + network path
2. Establish MCP server reliability SLA
3. Define simulation timeout & retry policy

### Implementation
```yaml
mcp_servers:
  - name: "ads_server"
    url: http://ads.example.com:8081
    enabled: true                         # ← Enable after verification
    reconnect_policy: exponential_backoff
    timeout_sec: 300
```

**Timeline**: 6-8 weeks (post-Phase 5)

---

## Known Gaps & Technical Debt

| ID | Item | Priority | Effort | Notes |
|---|---|---|---|---|
| **GAP-001** | Unit tests (calc_transistor_sizing.R) | P0 | 1 week | BLOCKER — no tests exist |
| **GAP-002** | API documentation (OpenAPI/swagger) | P1 | 3 days | None generated yet |
| **GAP-003** | Kubernetes manifests | P2 | 1 week | infra/k8s/ empty |
| **GAP-004** | Load testing suite | P2 | 2 weeks | No perf baselines |
| **GAP-005** | PA Manual Ch.2-6 | P1 | 4 weeks | Outline exists; 35% complete |
| **GAP-006** | Theory agent formula sharing | P1 | 3 days | Duplicate code with calc modules |

---

## Definition of Done

For each agent/module to be considered "Complete":
1. ✅ R6 class extends `BaseAgent`
2. ✅ LLM integration functional (or graceful fallback)
3. ✅ Unit tests ≥ 80% coverage
4. ✅ Integration test with server module
5. ✅ Documentation (docstrings + ADR)
6. ✅ Error handling & logging
7. ✅ Performance benchmarks (execution time < 5s)

---

## Success Metrics

| Metric | Current | Target |
|---|---|---|
| Unit test coverage | 5% | 75% |
| Agent implementation | 1/8 | 8/8 |
| Manual chapter completion | 35% | 100% |
| API response time (p95) | — | <500ms |
| Uptime | — | 99.5% |

---

**Last Updated**: 2026-04-02
**Owner**: RF Engineering Team
