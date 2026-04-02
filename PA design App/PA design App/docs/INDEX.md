# Documentation Index

Complete guide to PA Design App documentation, organized by use case and audience.

---

## 🚀 Getting Started

**New to the app?** Start here:

1. **[README.md](../README.md)** — Feature overview and quick start
2. **[QUICK_REFERENCE.md](../QUICK_REFERENCE.md)** — Common commands and patterns
3. **[DEVELOPMENT.md](DEVELOPMENT.md)** — Local setup & development workflow

---

## 👨‍💻 For Developers

### Setup & Installation
- **[DEVELOPMENT.md](DEVELOPMENT.md)** — Environment setup, testing, debugging
- **[DEPLOYMENT.md](DEPLOYMENT.md)** — Production deployment guide

### Code Patterns
- **[api-patterns/](api-patterns/)** — Recommended code patterns and conventions
  - Calculation modules (pure functions)
  - Server modules (Shiny reactivity)
  - AI agents (R6 classes)
  - Database access

### Architecture & Decisions
- **[architecture/](architecture/)** — Design philosophy and component library
  - `01_App_philosophy` — Guiding principles
  - `02_App_architecture_discussion` — Architecture evolution
  - `03_App_reorganization_proposal` — Structure improvements
  - `04_App_model_guidelines` — Data modeling conventions
  - `05_Knowledge_base_construction` — KB design
  - `06_Component_Library` — Reusable components
  - `07_Lessons_learnt` — Project insights
  - `08_Boundary_condition` — System boundaries
  - `9_Signals_database` — Signal handling
  - `10_RF_Tools` — RF utilities

### Decision Records
- **[decisions/](decisions/)** — Architecture Decision Records (ADRs)
  - **IMPLEMENTATION_ROADMAP.md** — Current phase status and priorities

---

## 📚 For RF Engineers & Users

### Reference Materials
- **[architecture/RF_Engg_books/](architecture/RF_Engg_books/)** — 30+ RF reference PDFs
- **[architecture/Ampleon_portfolio/](architecture/Ampleon_portfolio/)** — Device datasheets and PCB designs

### Working with the App
- **[QUICK_REFERENCE.md](../QUICK_REFERENCE.md)** — Common operations
- **[guides/QUICK_START_TEST_GUIDE.md](guides/QUICK_START_TEST_GUIDE.md)** — Testing workflow

---

## 🔧 For DevOps & Operations

### Deployment
- **[DEPLOYMENT.md](DEPLOYMENT.md)** — Complete deployment guide
  - Docker deployment
  - Manual deployment
  - Reverse proxy setup (Nginx/Apache)
  - Database management
  - Monitoring & logging
  - Troubleshooting & rollback

### Infrastructure
- **[infrastructure](../infra/)** — Docker, Kubernetes, deployment scripts

---

## 📊 Project History & Changelog

### Development Timeline
- **[changelog/INDEX.md](changelog/INDEX.md)** — Organized changelog and session history

### By Category
- **[changelog/fixes/](changelog/fixes/)** — Bug fixes and patches
- **[changelog/features/](changelog/features/)** — New features and enhancements
- **[changelog/sessions/](changelog/sessions/)** — Development session notes
- **[changelog/summaries/](changelog/summaries/)** — Project summaries
- **[changelog/technical/](changelog/technical/)** — Technical architecture docs

### Archive
- **[ARCHIVE_App_architecture_discussion.md](ARCHIVE_App_architecture_discussion.md)** — Historical architecture discussion
- **[ARCHIVE_reorganization_proposal.md](ARCHIVE_reorganization_proposal.md)** — Legacy reorganization notes

---

## 📈 Implementation Roadmap

**Current Status**: Rubix M1 (Q2 2026) — Transistor Design Level Complete

See **[decisions/IMPLEMENTATION_ROADMAP.md](decisions/IMPLEMENTATION_ROADMAP.md)** for:
- Current phase completion status
- Next priorities (AI Agents, Unit Tests, Production Hardening)
- Known gaps and technical debt
- Success metrics and timeline

---

## Directory Structure

```
docs/
├── INDEX.md                          ← You are here
├── README.md                         ← Architecture overview
├── DEVELOPMENT.md                    ← Dev guide
├── DEPLOYMENT.md                     ← Ops guide
│
├── api-patterns/                     ← Code patterns & conventions
├── architecture/                     ← Design philosophy & components
│   ├── RF_Engg_books/               ← Reference materials (30+ PDFs)
│   ├── Ampleon_portfolio/           ← Device datasheets
│   └── [design philosophy files]
├── decisions/                        ← Architecture Decision Records
└── guides/                           ← User guides
    └── QUICK_START_TEST_GUIDE.md
│
└── changelog/                        ← Complete change history
    ├── INDEX.md                      ← Changelog overview
    ├── fixes/                        ← Bug fixes (6 docs)
    ├── features/                     ← New features (6 docs)
    ├── sessions/                     ← Dev sessions (3 docs)
    ├── summaries/                    ← Overview summaries (4 docs)
    └── technical/                    ← Architecture docs (5 docs)
```

---

## Quick Links

| Role | Start Here |
|---|---|
| **New Developer** | [DEVELOPMENT.md](DEVELOPMENT.md) |
| **RF Engineer** | [README.md](../README.md) + [guides/QUICK_START_TEST_GUIDE.md](guides/QUICK_START_TEST_GUIDE.md) |
| **DevOps/Ops** | [DEPLOYMENT.md](DEPLOYMENT.md) |
| **Architect** | [decisions/IMPLEMENTATION_ROADMAP.md](decisions/IMPLEMENTATION_ROADMAP.md) |
| **Project Manager** | [changelog/INDEX.md](changelog/INDEX.md) |

---

## Contributing

When adding documentation:

1. **Bug fixes/patches** → `changelog/fixes/`
2. **New features** → `changelog/features/`
3. **Session notes** → `changelog/sessions/`
4. **Project summaries** → `changelog/summaries/`
5. **Architecture decisions** → `decisions/` (use ADR format)
6. **Code patterns** → `api-patterns/`
7. **User guides** → `guides/`

Update this INDEX.md when adding new docs.

---

**Last Updated**: 2026-04-02
**Maintainer**: RF Engineering Team
