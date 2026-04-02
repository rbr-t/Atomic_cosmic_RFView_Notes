# Framework Reuse Guide: Building New Apps from PA Design Architecture

**Version:** 1.0  
**Date:** February 28, 2026  
**Purpose:** Step-by-step guide to create new domain-specific apps using the PA Design App architecture as a template.

---

## 1. Introduction

This guide explains how to leverage the PA Design App architecture to build similar applications in other domains (antenna design, filter design, analog circuit design, etc.). The architecture has been designed with reusability in mind, separating domain-agnostic core systems from domain-specific plugins.

---

## 2. Prerequisites

### 2.1 Technical Knowledge Required
- R programming and Shiny framework
- Basic understanding of REST APIs
- Docker and containerization
- Database fundamentals (SQL + vector databases)
- Git version control

### 2.2 Tools & Infrastructure
- R (v4.3+) with Shiny
- PostgreSQL (v14+)
- Docker & Docker Compose
- Git repository
- (Optional) Cloud platform account (AWS/GCP/Azure)

---

## 3. Architecture Overview for Reuse

### 3.1 Reusable Core Components (Domain-Agnostic)

These components work for any technical domain:

| Component | Purpose | Reusability |
|-----------|---------|-------------|
| **Project Management** | Lifecycle management, milestones, tasks | 100% reusable |
| **Data Management** | Import/export, versioning, storage | 95% reusable (file formats may vary) |
| **State & Config Management** | User preferences, app state | 100% reusable |
| **Tagging & Metadata** | Classification and filtering | 100% reusable |
| **Security System** | Auth, authorization, encryption | 100% reusable |
| **Frontend Framework** | Shiny UI skeleton, responsive layout | 90% reusable (minor customization) |

### 3.2 Customizable Components (Domain-Specific)

These require domain customization:

| Component | Customization Level | What to Customize |
|-----------|---------------------|-------------------|
| **AI Agents** | 100% | Agent roles, expertise, prompts |
| **ML System** | 80% | Features, training data, models |
| **MCP Integrations** | 100% | External tools specific to domain |
| **Knowledge Base** | 100% | Domain literature, textbooks, papers |
| **Chatbot** | 60% | Domain-specific prompts and knowledge |
| **Strategy Manager** | 80% | Decision frameworks for domain |
| **Debug Manager** | 70% | Common failure modes and fixes |

---

## 4. Step-by-Step Framework Adaptation

### Step 1: Define Your Domain

**Example Domains:**
- Antenna Design (patch, dipole, array)
- RF Filter Design (Butterworth, Chebyshev, elliptic)
- Analog IC Design (OpAmps, ADCs, PLLs)
- Digital Signal Processing (filter implementation, codec design)
- Power Electronics (DC-DC converters, inverters)

**Exercise: Fill out the domain worksheet**

```yaml
domain_definition:
  name: "Antenna Design App"
  description: "End-to-end antenna design from specs to measurement"
  
  design_lifecycle:
    - "Requirements & Specs"
    - "Antenna Type Selection"
    - "Theoretical Calculations (radiation pattern, impedance)"
    - "EM Simulation (HFSS, CST)"
    - "Geometry Optimization"
    - "Fabrication"
    - "Measurement & Characterization"
    - "Lessons Learned"
  
  key_metrics:
    - "Gain (dBi)"
    - "Bandwidth (%)"
    - "VSWR"
    - "Radiation Efficiency (%)"
    - "Axial Ratio (dB, for circular pol)"
  
  external_tools:
    - "HFSS"
    - "CST Microwave Studio"
    - "VNA"
```

---

### Step 2: Clone the Core Framework

**Repository Structure:**

```bash
# Clone the PA Design App repository
git clone <repo-url> antenna-design-app
cd antenna-design-app

# Create a new branch for your domain
git checkout -b domain/antenna-design

# Directory structure (initial)
├── core/                    # DO NOT MODIFY (domain-agnostic)
│   ├── project_mgmt/
│   ├── data_mgmt/
│   ├── security/
│   └── ...
├── plugins/
│   └── rf_pa_design/        # Existing PA design plugin
├── config/
│   └── pa_design.yaml       # Existing config
└── R/
    └── app.R                # Main Shiny app
```

---

### Step 3: Create Your Domain Plugin

**Create plugin directory:**

```bash
mkdir -p plugins/antenna_design
cd plugins/antenna_design
```

**Plugin structure:**

```
plugins/antenna_design/
├── agents/                  # Domain-specific AI agents
│   ├── antenna_type_agent.R
│   ├── radiation_agent.R
│   ├── feeding_network_agent.R
│   └── measurement_agent.R
├── knowledge_base/          # Domain literature
│   ├── embeddings/          # Vector embeddings
│   └── references.bib       # Citations
├── ml_models/               # ML models for prediction
│   ├── gain_predictor.pkl
│   └── bandwidth_predictor.pkl
├── ui_modules/              # Custom Shiny UI modules
│   ├── radiation_pattern_viewer.R
│   └── smith_chart_module.R
├── mcp_servers/             # MCP integrations
│   ├── hfss_mcp_server.js
│   └── vna_mcp_server.py
└── config.yaml              # Plugin configuration
```

---

### Step 4: Define AI Agents for Your Domain

**Agent Definition Template:**

Create `plugins/antenna_design/agents/antenna_type_agent.R`:

```r
# Antenna Type Selection Agent
# Recommends antenna type based on specs

AntennaTypeAgent <- R6Class("AntennaTypeAgent",
  inherit = BaseAgent,  # Inherits from core/agents/base_agent.R
  
  public = list(
    name = "Antenna Type Agent",
    expertise = "Antenna topologies, radiation characteristics, size constraints",
    
    # Main entry point
    execute = function(task) {
      # task = list(context, specs, requirements)
      
      # Extract specs
      freq <- task$specs$frequency
      gain_target <- task$specs$gain
      size_constraint <- task$specs$max_size
      polarization <- task$specs$polarization  # linear, circular
      
      # Query knowledge base
      kb_results <- self$query_knowledge_base(
        query = paste("antenna types for", freq, "GHz with", polarization, "polarization"),
        top_k = 5
      )
      
      # LLM reasoning
      prompt <- self$build_prompt(specs = task$specs, kb_context = kb_results)
      llm_response <- self$call_llm(prompt)
      
      # Validate response
      validated <- self$validate_response(llm_response, task$specs)
      
      return(list(
        recommended_types = validated$types,
        rationale = validated$explanation,
        confidence = validated$confidence,
        references = kb_results$citations
      ))
    },
    
    # Prompt engineering
    build_prompt = function(specs, kb_context) {
      prompt <- paste0(
        "You are an expert antenna design engineer. Based on the following specs:\n",
        "Frequency: ", specs$frequency, " GHz\n",
        "Target Gain: ", specs$gain, " dBi\n",
        "Max Size: ", specs$max_size, " mm\n",
        "Polarization: ", specs$polarization, "\n\n",
        "Context from literature:\n", kb_context$text, "\n\n",
        "Recommend the top 3 antenna types and explain tradeoffs (size, bandwidth, gain, complexity)."
      )
      return(prompt)
    },
    
    # Validate LLM output
    validate_response = function(llm_response, specs) {
      # Check if recommended antennas are physically feasible
      # Example: Patch antenna at 1 GHz is too large if max_size = 10mm
      
      # Parse LLM response
      types <- extract_antenna_types(llm_response)
      
      # Physics-based validation
      for (type in types) {
        size <- self$estimate_size(type, specs$frequency)
        if (size > specs$max_size) {
          # Flag as infeasible
          type$feasible <- FALSE
          type$reason <- "Size exceeds constraint"
        } else {
          type$feasible <- TRUE
        }
      }
      
      return(list(
        types = types,
        explanation = llm_response,
        confidence = calculate_confidence(types)
      ))
    }
  )
)
```

**Repeat for all domain agents:**
- Radiation Pattern Agent (analyzes far-field patterns)
- Feeding Network Agent (impedance matching)
- EM Simulation Agent (HFSS/CST integration)
- Measurement Agent (VNA data analysis)

---

### Step 5: Configure MCP Integrations

**Example: HFSS MCP Server**

Create `plugins/antenna_design/mcp_servers/hfss_mcp_server.js`:

```javascript
// MCP Server for HFSS integration
const { MCPServer } = require('@modelcontextprotocol/sdk');

const server = new MCPServer({
  name: 'hfss-mcp-server',
  version: '1.0.0'
});

// Tool: Launch HFSS simulation
server.addTool({
  name: 'hfss_run_simulation',
  description: 'Run HFSS simulation for antenna design',
  parameters: {
    project_file: { type: 'string', description: 'Path to .aedt file' },
    frequency_range: { type: 'array', description: '[fmin, fmax] in GHz' },
    design_params: { type: 'object', description: 'Antenna geometry parameters' }
  },
  handler: async (params) => {
    // Launch HFSS via COM API (Windows) or scripting interface
    const hfss = await launchHFSS();
    const project = await hfss.loadProject(params.project_file);
    
    // Set design parameters
    for (const [key, value] of Object.entries(params.design_params)) {
      project.setVariable(key, value);
    }
    
    // Run simulation
    const results = await project.analyze();
    
    // Export S-parameters, radiation pattern
    const s_params = await project.exportSParams();
    const radiation = await project.exportRadiationPattern();
    
    return {
      status: 'success',
      s_parameters: s_params,
      radiation_pattern: radiation
    };
  }
});

server.listen(8081);
```

**Register MCP server in config:**

```yaml
# config/antenna_design.yaml
mcp_servers:
  - name: "hfss_server"
    url: "http://localhost:8081"
    tool_prefix: "hfss_"
  - name: "vna_server"
    url: "http://localhost:8082"
    tool_prefix: "vna_"
```

---

### Step 6: Build Domain-Specific UI Modules

**Example: Radiation Pattern Viewer**

Create `plugins/antenna_design/ui_modules/radiation_pattern_viewer.R`:

```r
# Shiny module for 3D radiation pattern visualization

radiationPatternUI <- function(id) {
  ns <- NS(id)
  tagList(
    h3("Radiation Pattern"),
    plotlyOutput(ns("pattern_3d")),
    sliderInput(ns("phi_cut"), "Phi Plane Cut (deg)", 0, 360, 0),
    sliderInput(ns("theta_cut"), "Theta Plane Cut (deg)", 0, 180, 90)
  )
}

radiationPatternServer <- function(id, pattern_data) {
  moduleServer(id, function(input, output, session) {
    
    output$pattern_3d <- renderPlotly({
      # pattern_data: list(theta, phi, gain_dBi)
      
      # Convert spherical to Cartesian
      x <- pattern_data$gain * sin(pattern_data$theta) * cos(pattern_data$phi)
      y <- pattern_data$gain * sin(pattern_data$theta) * sin(pattern_data$phi)
      z <- pattern_data$gain * cos(pattern_data$theta)
      
      # 3D surface plot
      plot_ly(x = x, y = y, z = z, type = "surface", colorscale = "Jet") %>%
        layout(
          scene = list(
            xaxis = list(title = "X (dBi)"),
            yaxis = list(title = "Y (dBi)"),
            zaxis = list(title = "Z (dBi)")
          )
        )
    })
  })
}
```

**Integrate into main app:**

```r
# R/app.R
ui <- fluidPage(
  # ... existing UI ...
  radiationPatternUI("rad_pattern")
)

server <- function(input, output, session) {
  # ... existing server logic ...
  
  # Call module
  radiationPatternServer("rad_pattern", pattern_data = reactive(current_pattern_data()))
}
```

---

### Step 7: Populate Knowledge Base

**Curate domain literature:**

1. **Collect sources:**
   - Textbooks: Balanis "Antenna Theory", Stutzman "Antenna Theory and Design"
   - IEEE papers on specific antenna types
   - Application notes from vendors

2. **Extract text and create embeddings:**

```bash
# Python script to create embeddings
python scripts/create_embeddings.py \
  --input plugins/antenna_design/knowledge_base/textbooks/ \
  --output plugins/antenna_design/knowledge_base/embeddings/ \
  --model text-embedding-ada-002
```

3. **Store in vector database:**

```r
# R script to load embeddings into Chroma
library(chromadb)

client <- chromadb_client()
collection <- client$create_collection("antenna_knowledge")

# Load embeddings
embeddings <- read_embeddings("plugins/antenna_design/knowledge_base/embeddings/")
collection$add(
  documents = embeddings$text,
  embeddings = embeddings$vectors,
  metadatas = embeddings$metadata  # citation info
)
```

---

### Step 8: Train ML Models (Optional)

**If you have historical data:**

1. **Feature engineering:**

```python
# Python: Extract features from past antenna projects
import pandas as pd

projects = pd.read_csv("historical_antenna_projects.csv")

# Features: frequency, size, substrate, polarization
# Target: achieved gain

X = projects[['frequency_ghz', 'size_mm', 'substrate_er', 'polarization_encoded']]
y = projects['measured_gain_dbi']

# Train model
from sklearn.ensemble import RandomForestRegressor

model = RandomForestRegressor(n_estimators=100)
model.fit(X, y)

# Save model
import joblib
joblib.dump(model, "plugins/antenna_design/ml_models/gain_predictor.pkl")
```

2. **Integrate model into agent:**

```r
# In radiation_agent.R
predict_gain <- function(specs) {
  # Load model
  model <- py_load_object("plugins/antenna_design/ml_models/gain_predictor.pkl")
  
  # Prepare features
  features <- data.frame(
    frequency_ghz = specs$frequency,
    size_mm = specs$size,
    substrate_er = specs$substrate$er,
    polarization_encoded = ifelse(specs$polarization == "linear", 0, 1)
  )
  
  # Predict
  predicted_gain <- py_call(model$predict, features)
  return(predicted_gain)
}
```

---

### Step 9: Update Configuration Files

**Create app-specific config:**

```yaml
# config/antenna_design.yaml
app:
  name: "Antenna Design Assistant"
  version: "1.0.0"
  domain: "antenna_design"

plugin:
  name: "antenna_design"
  path: "plugins/antenna_design"

agents:
  - name: "AntennaTypeAgent"
    enabled: true
    model: "gpt-4"
  - name: "RadiationAgent"
    enabled: true
    model: "gpt-4"
  - name: "FeedingNetworkAgent"
    enabled: true
    model: "gpt-4"

mcp_servers:
  - name: "hfss_server"
    url: "http://localhost:8081"
  - name: "vna_server"
    url: "http://localhost:8082"

knowledge_base:
  vector_db: "chroma"
  collection: "antenna_knowledge"
  embedding_model: "text-embedding-ada-002"

ml_models:
  gain_predictor:
    path: "plugins/antenna_design/ml_models/gain_predictor.pkl"
    enabled: true

ui:
  theme: "dark"
  logo: "plugins/antenna_design/assets/logo.png"
  primary_color: "#ff7f11"
```

---

### Step 10: Test and Iterate

**Testing checklist:**

- [ ] **Unit tests:** Test each agent independently
  ```r
  testthat::test_file("tests/test_antenna_type_agent.R")
  ```

- [ ] **Integration tests:** Test agent interactions
  ```r
  # Test: AntennaTypeAgent → RadiationAgent handoff
  ```

- [ ] **UI tests:** Manual testing of Shiny modules
  - Verify radiation pattern viewer renders correctly
  - Test data import/export

- [ ] **MCP tests:** Verify HFSS/VNA integration
  ```bash
  curl -X POST http://localhost:8081/hfss_run_simulation \
    -d '{"project_file": "test.aedt", ...}'
  ```

- [ ] **End-to-end test:** Full design flow
  - Create project → Select antenna type → Run simulation → View results

---

## 5. Deployment

### 5.1 Local Deployment (Docker)

**Dockerfile (generated):**

```dockerfile
FROM rocker/shiny:4.3

# Install R packages
RUN R -e "install.packages(c('shiny', 'plotly', 'DT', 'R6', 'reticulate'))"

# Copy app
COPY . /srv/shiny-server/antenna-design-app

# Expose port
EXPOSE 3838

# Run app
CMD ["/usr/bin/shiny-server"]
```

**docker-compose.yml:**

```yaml
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3838:3838"
    volumes:
      - ./data:/data
    environment:
      - DB_HOST=postgres
  
  postgres:
    image: postgres:14
    environment:
      POSTGRES_DB: antenna_design
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data
  
  chroma:
    image: chromadb/chroma:latest
    ports:
      - "8000:8000"

volumes:
  pgdata:
```

**Launch:**

```bash
docker-compose up -d
# Access app at http://localhost:3838
```

### 5.2 Production Deployment (Kubernetes)

**See `deployment/kubernetes/` for full manifests.**

---

## 6. Maintenance and Evolution

### 6.1 Adding New Features

**Example: Add a new agent**

1. Create agent file: `plugins/antenna_design/agents/new_agent.R`
2. Inherit from `BaseAgent` and implement `execute()` method
3. Register in `config/antenna_design.yaml`
4. Write tests: `tests/test_new_agent.R`
5. Update documentation

### 6.2 Updating Knowledge Base

```bash
# Add new papers/textbooks
cp new_paper.pdf plugins/antenna_design/knowledge_base/papers/

# Re-generate embeddings
python scripts/update_embeddings.py --source papers/new_paper.pdf

# Reload vector DB
Rscript scripts/reload_vector_db.R
```

### 6.3 Versioning

- Use semantic versioning (MAJOR.MINOR.PATCH)
- Tag releases: `git tag v1.0.0`
- Changelog: Update `CHANGELOG.md` for each release

---

## 7. Case Study: From PA Design to Antenna Design

| Aspect | PA Design App | Antenna Design App | Changes Made |
|--------|---------------|-------------------|--------------|
| **Lifecycle** | First principles → Tapeout → Measurement | Requirements → EM Sim → Fabrication → Measurement | Renamed phases |
| **Key Metrics** | PAE, Gain, Pout | Gain, Bandwidth, VSWR | Different metrics |
| **Agents** | Theory, Architecture, Simulation | Antenna Type, Radiation, Feeding Network | New agent roles |
| **External Tools** | ADS, AWR | HFSS, CST | Different MCP servers |
| **Knowledge Base** | PA textbooks, IEEE papers | Antenna textbooks, IEEE papers | Different literature |
| **UI Modules** | Load-pull contours, Smith charts | Radiation patterns, Smith charts | 50% overlap |

**Time to adapt:** ~6-8 weeks for a skilled team (2-3 developers)

---

## 8. Common Pitfalls and How to Avoid Them

| Pitfall | Impact | Mitigation |
|---------|--------|------------|
| **Modifying core components** | Breaks updates from main framework | Always work in plugins, never edit `core/` |
| **Hardcoding domain logic in UI** | UI becomes unmaintainable | Use Shiny modules and separate business logic |
| **Ignoring validation in agents** | AI hallucinations propagate | Always validate agent outputs with physics/data |
| **Poor knowledge base curation** | Chatbot gives incorrect answers | Vet all sources, use citations, review embeddings |
| **Skipping security** | Data breaches | Implement auth/encryption from day 1, not later |

---

## 9. Support and Resources

### 9.1 Documentation
- [R Shiny Guide](https://shiny.rstudio.com/)
- [MCP Protocol Spec](https://modelcontextprotocol.io/)
- [Chroma Vector DB Docs](https://docs.trychroma.com/)

### 9.2 Community
- GitHub Discussions: Ask questions and share plugins
- Slack Channel: #framework-users

### 9.3 Training
- Video tutorials: ["Building Your First App from the Framework"](https://example.com/tutorials)
- Live workshops: Quarterly training sessions

---

## 10. Checklist: Framework Adaptation

Use this checklist when creating a new app:

- [ ] Step 1: Domain definition worksheet completed
- [ ] Step 2: Core framework cloned
- [ ] Step 3: Plugin directory created
- [ ] Step 4: AI agents defined and implemented
- [ ] Step 5: MCP integrations configured
- [ ] Step 6: UI modules built
- [ ] Step 7: Knowledge base populated
- [ ] Step 8: ML models trained (if applicable)
- [ ] Step 9: Configuration files updated
- [ ] Step 10: Tests written and passing
- [ ] Deployment: Docker Compose setup tested
- [ ] Documentation: README and user guide written
- [ ] Review: Peer review of code and architecture

---

## 11. Example Gallery

**Apps built from this framework:**

1. **Antenna Design App** (this guide's example)
2. **RF Filter Design App** (Butterworth, Chebyshev, elliptic filters)
3. **Analog IC Design App** (OpAmp design from specs to layout)
4. **Power Electronics App** (DC-DC converter design)

(Screenshots and demos available in `examples/` directory)

---

## 12. Contributing Back to the Framework

If you develop a useful plugin or improvement:

1. **Fork the main framework repo**
2. **Submit a pull request** with your plugin in `plugins/community/`
3. **Documentation:** Include README, examples, and tests
4. **License:** Ensure compatibility (MIT/Apache 2.0)

**Benefits of contributing:**
- Your plugin maintained by community
- Appear in official plugin gallery
- Recognition in contributors list

---

## 13. Conclusion

The PA Design App architecture is designed for maximum reusability. By following this guide, you can adapt it to any technical domain in 6-12 weeks. The key is:

1. **Preserve the core:** Don't modify domain-agnostic components
2. **Plug in domain logic:** Use the plugin system for customization
3. **Test thoroughly:** Ensure agents, MCP servers, and UI work correctly
4. **Iterate based on user feedback:** Continuous improvement

**Next Steps:**
- Read the full [Architecture Specification](ARCHITECTURE_SPEC.md)
- Explore the [PA Design Plugin](../plugins/rf_pa_design/) for reference
- Join the community and start building!

---

**Questions? Contact: [framework-support@example.com]**
