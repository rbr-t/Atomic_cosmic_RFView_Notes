# PA Design App - RF Power Amplifier Design Assistant

A comprehensive R Shiny application for end-to-end RF Power Amplifier design and development, from first principles through measurement and lessons learned.

## 🎯 Overview

The PA Design App is an intelligent, AI-powered platform that assists RF engineers in designing power amplifiers with:

- **Data-Driven Design:** All decisions backed by calculations, simulations, and measurements
- **AI Assistance:** 8 specialized AI agents for theory, architecture, simulation, layout, measurement, debugging, documentation, and strategy
- **Knowledge Capture:** Learn from every project with tagging, metadata, and searchable knowledge base
- **End-to-End Workflow:** From first principles → measurement → lessons learned
- **Reproducible:** Complete audit trail and versioned designs

## 📁 Project Structure

```
PA design App/
├── R/
│   └── app.R                      # Main Shiny application
├── core/                          # Domain-agnostic core systems
│   ├── project_mgmt/              # Project lifecycle management
│   ├── data_mgmt/                 # Data import/export/storage
│   ├── security/                  # Authentication & authorization
│   ├── state_config/              # Configuration management
│   ├── tagging_metadata/          # Tagging system
│   └── ai_agents/                 # Base AI agent framework
│       ├── base_agent.R
│       └── agent_manager.R
├── plugins/                       # Domain-specific plugins
│   └── rf_pa_design/
│       ├── agents/                # RF PA specific agents
│       │   └── theory_agent.R
│       ├── knowledge_base/        # RF literature & embeddings
│       ├── ui_modules/            # Custom UI components
│       └── mcp_servers/           # MCP integrations (ADS, AWR, Lab)
├── config/
│   └── app_config.yaml            # Application configuration
├── data/                          # Data storage
│   ├── projects/                  # Project files
│   ├── uploads/                   # Uploaded data
│   └── exports/                   # Exported results
├── database/
│   └── init.sql                   # Database schema
├── logs/                          # Application logs
├── tests/                         # Unit and integration tests
├── architecture_prototype/        # Architecture documentation
│   ├── ARCHITECTURE_SPEC.md
│   ├── FRAMEWORK_REUSE_GUIDE.md
│   ├── index.html
│   └── README.md
├── Dockerfile                     # Docker container definition
├── docker-compose.yml             # Multi-container setup
└── README.md                      # This file
```

## 🚀 Quick Start

### Option 1: Docker (Recommended)

```bash
# Clone or navigate to the PA design App directory
cd "PA design App"

# Start all services (app + database + vector DB)
docker-compose up -d

# Access the app at http://localhost:3838
# Access pgAdmin at http://localhost:5050 (admin@padesign.local / admin)
```

### Option 2: Local Development

#### Prerequisites

- R (v4.3+)
- PostgreSQL (v14+)
- RStudio (optional but recommended)

#### Install R Dependencies

```r
install.packages(c(
    'shiny',
    'shinydashboard',
    'shinyjs',
    'plotly',
    'DT',
    'R6',
    'yaml',
    'DBI',
    'pool',
    'RPostgres',
    'httr',
    'jsonlite',
    'readxl',
    'uuid'
))
```

#### Set Up Database

```bash
# Create database
createdb pa_design

# Initialize schema
psql pa_design < database/init.sql
```

#### Configure Environment

```bash
# Set environment variables
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=pa_design
export DB_USER=admin
export DB_PASSWORD=secret
export OPENAI_API_KEY=your_openai_key_here  # Optional
```

#### Run the App

```r
# From R or RStudio
setwd("PA design App")
shiny::runApp("R/app.R", port = 3838)
```

Access at `http://localhost:3838`

## 🧩 Core Features

### 1. Project Management
- Create and manage multiple PA design projects
- Track project lifecycle from concept to measurement
- Milestone tracking and progress monitoring

### 2. Theoretical Calculation Module ⚡
**Status:** Ready for use

- Load-pull calculations (optimal load impedance)
- Matching network synthesis (L-section, Pi, T networks)
- Bode-Fano limit checking
- Theory Agent for RF fundamentals Q&A

### 3. AI Agents 🤖

| Agent | Purpose | Status |
|-------|---------|--------|
| **Theory Agent** | RF fundamentals, equations, limits | ✅ Implemented |
| **Architecture Agent** | PA class/topology selection | 🚧 Coming soon |
| **Simulation Agent** | ADS/AWR integration | 🚧 Coming soon |
| **Layout Agent** | RF layout review | 🚧 Coming soon |
| **Measurement Agent** | Lab equipment control & analysis | 🚧 Coming soon |
| **Documentation Agent** | Report generation | 🚧 Coming soon |
| **Debug Agent** | Troubleshooting | 🚧 Coming soon |
| **Strategy Agent** | High-level planning | 🚧 Coming soon |

### 4. Data Management
- Import: CSV, Excel, Touchstone (.sNp), MDIF
- Export: CSV, JSON, RDS
- Versioned datasets with provenance

### 5. Tagging & Metadata
- Tag projects, datasets, and designs
- Multi-dimensional filtering (architecture, frequency, cost, performance)

### 6. Security
- Role-based access control (RBAC): Admin, Designer, Viewer
- Session management
- Audit logging

## 📚 Theoretical Calculation Module Usage

### Example: Load-Pull Calculation

1. Navigate to **Design Flow → Theoretical Calc**
2. Select or create a project
3. Enter supply voltage (Vdd) and max current (Imax)
4. Click **Calculate Load Impedance**
5. View optimal load impedance and expected power output

### Example: Matching Network Synthesis

1. Enter source impedance (typically 50Ω)
2. Enter load impedance (from load-pull calculation)
3. Set operating frequency
4. Select matching network type (L-section recommended for narrowband)
5. Click **Synthesize Matching Network**
6. Get component values (inductors in nH, capacitors in pF)

### Example: Ask Theory Agent

1. Type your question in the text area, e.g.:
   - "What are the fundamental PAE limits for Class-A?"
   - "Explain Bode-Fano limit for matching a 10Ω load"
   - "What is the optimal architecture for 60% PAE at 2.4 GHz?"
2. Click **Ask Theory Agent**
3. Review AI-powered answer with references

## 🔧 Configuration

Edit `config/app_config.yaml`:

```yaml
ai_agents:
  enabled: true
  model: "gpt-4"           # or "gpt-3.5-turbo", "claude-3-opus"
  confidence_threshold: 0.7

theme:
  mode: "dark"             # "dark", "light", "colorblind"
  accent_color: "#ff7f11"

units:
  frequency: "GHz"
  power: "dBm"
  impedance: "Ohm"
```

## 🧪 Testing

```r
# Run unit tests
testthat::test_dir("tests")

# Test specific module
testthat::test_file("tests/test_theory_agent.R")
```

## 📊 Database Schema

- **projects:** Project metadata, specs, status
- **datasets:** Measurement and simulation data
- **tags:** Multi-dimensional tagging
- **users:** User accounts and roles
- **agent_logs:** AI agent activity audit trail
- **simulations:** Simulation runs and results

## 🛠️ Development Roadmap

### Phase 1: Foundation ✅
- [x] Project management system
- [x] Data management (basic)
- [x] Theoretical calculation module
- [x] Theory Agent
- [x] UI skeleton with dashboard

### Phase 2: AI & Integration (In Progress)
- [ ] Architecture Agent
- [ ] Simulation Agent with MCP (ADS/AWR)
- [ ] Knowledge base with vector DB
- [ ] Chatbot interface

### Phase 3: Advanced Features
- [ ] Layout Agent
- [ ] Measurement Agent
- [ ] ML prediction models
- [ ] Multi-agent collaboration
- [ ] Interactive report builder

### Phase 4: Production
- [ ] Security hardening
- [ ] Performance optimization
- [ ] Kubernetes deployment
- [ ] User documentation

## 🤝 Contributing

See [FRAMEWORK_REUSE_GUIDE.md](architecture_prototype/FRAMEWORK_REUSE_GUIDE.md) for:
- How to add new agents
- How to create domain-specific plugins
- How to extend the framework for other applications

## 📖 Documentation

- [Architecture Specification](architecture_prototype/ARCHITECTURE_SPEC.md) - Detailed system design
- [Framework Reuse Guide](architecture_prototype/FRAMEWORK_REUSE_GUIDE.md) - Building similar apps
- [App Architecture Discussion](App%20architecture%20discussion) - Original requirements

## 🔐 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_HOST` | PostgreSQL host | localhost |
| `DB_PORT` | PostgreSQL port | 5432 |
| `DB_NAME` | Database name | pa_design |
| `DB_USER` | Database user | admin |
| `DB_PASSWORD` | Database password | secret |
| `OPENAI_API_KEY` | OpenAI API key (optional) | - |

## 📝 License

MIT License - See LICENSE file for details

## 🆘 Support

- GitHub Issues: Report bugs and feature requests
- Email: [Your contact email]
- Documentation: See `architecture_prototype/` folder

## 🎯 Current Status

**Version:** 1.0.0-alpha  
**Status:** Development - Theoretical Calculation Module Ready  
**Last Updated:** February 28, 2026

The app skeleton is complete with a working Theoretical Calculation module featuring:
- Load-pull calculations
- Matching network synthesis
- Theory Agent integration
- Project management
- Dashboard with metrics

**Next Step:** Implementation of Architecture Agent and first-principles validation module.

---

**Built with ❤️ for RF engineers by RF engineers**
