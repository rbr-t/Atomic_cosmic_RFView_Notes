# IFX Activity Dashboard - Visual Architecture

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  IFX Activity Dashboard                      │
│                 (Web-based Viewer)                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│          Master_html_myActivity_IFX.html                     │
│  ┌────────────┐  ┌──────────────────────────────────┐      │
│  │    TOC     │  │        Report Viewer (iframe)     │      │
│  │  Sidebar   │  │                                   │      │
│  │            │  │  [Selected Report Displays Here] │      │
│  │ ▸ IFX      │  │                                   │      │
│  │   ▾ Admin  │  │                                   │      │
│  │     • Docs │──┼─▶ Loads HTML file                │      │
│  │   ▸ Projects│  │                                   │      │
│  │   ▸ PRD    │  │                                   │      │
│  └────────────┘  └──────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## File Generation Workflow

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│  .Rmd Files  │         │  R Studio/   │         │  .html Files │
│  (Source)    │  ─────▶ │   knitr      │  ─────▶ │  (Output)    │
│              │         │  (Renderer)  │         │              │
└──────────────┘         └──────────────┘         └──────────────┘
      │                                                   │
      │ References source data                           │
      ▼                                                   ▼
┌──────────────┐                                  ┌──────────────┐
│  01_Admin/   │                                  │ Viewable in  │
│  02_Projects │                                  │  Browser     │
│  03_PRD/     │                                  │              │
│  etc...      │                                  └──────────────┘
└──────────────┘
```

## Directory Structure & Data Flow

```
IFX_2022_2025/
│
├─ Report_generator_rmd/           ◄── MAIN WORKING DIRECTORY
│  ├─ Master_html_myActivity_IFX.Rmd    (Dashboard source)
│  ├─ Master_html_myActivity_IFX.html   (Dashboard output) ◄── OPEN THIS
│  │
│  ├─ IFX-Administration-2022_2026.Rmd  (Report source)
│  ├─ IFX-Administration-2022_2026.html (Report output)
│  │    │
│  │    └──reads data from──▶ ../01_Administration/
│  │
│  ├─ IFX-Business_Trips-2022_2026.Rmd
│  ├─ IFX-Business_Trips-2022_2026.html
│  │    │
│  │    └──reads data from──▶ ../06_Business_Trips/
│  │
│  └─ (More .Rmd/.html pairs...)
│
├─ 00_Master_html_file/            ◄── COPY OF HTML FILES
│  └─ (Mirror of all .html files)
│
├─ 01_Administration/              ◄── SOURCE DATA FOLDERS
├─ 02_Projects/
├─ 03_PRD/
├─ 04_Conferences/
├─ 05_Study_Material/
├─ 06_Business_Trips/
├─ 07_Technical_reports/
├─ 08_Competition/
├─ 09_My_presentations/
└─ 10_IFX_internal_trainings/
```

## How Links Work After Path Fix

### Before (Broken)
```
.Rmd File Location: /workspaces/.../Report_generator_rmd/IFX-Admin.Rmd
                            │
                            │ Contains hardcoded path:
                            │ "C:/Users/talluribhaga/.../01_Administration/"
                            │
                            ▼
                     ❌ ERROR: Path not found
```

### After (Working)
```
.Rmd File Location: /workspaces/.../Report_generator_rmd/IFX-Admin.Rmd
                            │
                            │ Contains relative path:
                            │ "../01_Administration/"
                            │
                            ▼
              Resolves to: /workspaces/.../01_Administration/
                            │
                            ▼
                     ✅ SUCCESS: Path found
```

## Relative Path Resolution

```
Starting from:  Report_generator_rmd/IFX-Admin.Rmd
                         │
Path: "../"              │ (Go up one level)
                         ▼
Arrives at:      IFX_2022_2025/
                         │
Path: "01_Administration/"│
                         ▼
Final location:  IFX_2022_2025/01_Administration/  ✓
```

## User Interaction Flow

```
┌────────────────────────────────────────────────────────────┐
│                    USER ACTIONS                            │
└────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ 1. Open      │  │ 2. Click     │  │ 3. View      │
│ Master.html  │  │ Category     │  │ Report       │
│ in Browser   │  │ in TOC       │  │ in iframe    │
└──────────────┘  └──────────────┘  └──────────────┘
```

## Report Categories & Files Mapping

```
Dashboard TOC Structure          Generated From              Source Data
═══════════════════════         ════════════════            ═══════════════

IFX
├─ Administration              IFX-Administration.Rmd  ──▶  01_Administration/
├─ Business Trips              IFX-Business_Trips.Rmd  ──▶  06_Business_Trips/
├─ Conferences                 IFX-Conference_Pres.Rmd ──▶  04_Conferences/
├─ My Presentations            IFX-My_presentation.Rmd ──▶  09_My_presentations/
├─ Organization Chart          IFX-Organization.Rmd    ──▶  (embedded data)
├─ Personal Review (PRD)       IFX-Personal_review.Rmd ──▶  03_PRD/
├─ Projects                    
│  ├─ Competition Reports      IFX-Project-Compet.Rmd  ──▶  08_Competition/
│  ├─ PAM_B_2023              IFX-Project-PAM_B.Rmd   ──▶  02_Projects/
│  └─ Tx_Baseline_2022        IFX-Project-Tx.Rmd      ──▶  02_Projects/
├─ Study Materials             IFX-Study_Material.Rmd  ──▶  05_Study_Material/
├─ Technical Reports           IFX-Technical_Rep.Rmd   ──▶  07_Technical_reports/
├─ Trainings (Internal)        IFX-Trainings.Rmd       ──▶  10_IFX_internal_trainings/
└─ Offboarding                 IFX-offboarding.Rmd     ──▶  (embedded data)
```

## Path Fix Implementation

```
Python Script: fix_ifx_paths.py
        │
        ├─ Scans: Report_generator_rmd/*.Rmd
        │
        ├─ Finds:  "C:/Users/talluribhaga/Documents/My_IFX_activity/..."
        │
        ├─ Replaces with: "../XX_FolderName/"
        │
        ├─ Creates: *.Rmd.backup (safety copies)
        │
        └─ Updates: All 14 .Rmd files

Result: ✅ All paths now work from any location
```

## Rendering Process Detail

```
┌──────────────────────────────────────────────────────────────┐
│                  R Markdown Rendering                         │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│  Step 1: Read .Rmd file                                     │
│  ├─ YAML header (title, theme, CSS)                        │
│  ├─ R code chunks (data processing)                        │
│  └─ Markdown content (text, formatting)                    │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│  Step 2: Execute R code chunks                              │
│  ├─ Load source data from ../XX_Folder/                    │
│  ├─ Process data (tables, plots, summaries)                │
│  └─ Generate HTML elements (htmltools)                     │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│  Step 3: Convert Markdown → HTML                            │
│  ├─ Parse markdown syntax                                   │
│  ├─ Apply theme (yeti) and CSS                            │
│  └─ Embed generated content                                │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────────┐
│  Step 4: Write output .html file                            │
│  └─ Self-contained HTML document ✓                         │
└────────────────────────────────────────────────────────────┘
```

## Technology Stack Layers

```
┌─────────────────────────────────────┐
│     Browser (User Interface)        │  ◄── Chrome, Firefox, Safari, Edge
├─────────────────────────────────────┤
│     HTML/CSS/JavaScript             │  ◄── Bootstrap (yeti theme)
├─────────────────────────────────────┤
│     R Markdown Output               │  ◄── Generated .html files
├─────────────────────────────────────┤
│     R Processing Layer              │  ◄── htmltools, knitr, rmarkdown
├─────────────────────────────────────┤
│     Data Layer                      │  ◄── Excel, PDF, images, text files
├─────────────────────────────────────┤
│     File System                     │  ◄── Organized folder structure
└─────────────────────────────────────┘
```

## Benefits of Relative Paths

```
Old Approach (Hardcoded)              New Approach (Relative)
══════════════════════                ══════════════════════

❌ Works only on:                      ✅ Works on:
   - Your Windows PC                     - Any Windows PC
   - Specific user account               - Any Mac
   - Exact drive letter                  - Any Linux system
                                        - Any cloud storage
                                        - Any shared drive

❌ Breaks when:                        ✅ Never breaks:
   - Copying to different PC            - Copy anywhere
   - Changing username                  - Rename parent folders
   - Moving folders                     - Move entire structure
   - Sharing with colleagues            - Share freely

❌ Version control:                    ✅ Version control:
   - Personal paths in code             - Clean, generic paths
   - Can't share via Git                - Git-friendly
   - Manual fixes needed                - Works for everyone
```

## Folder Naming Convention

```
Format: XX_CategoryName

Where:
  XX = Two-digit number (for sorting)
  Category = Descriptive name

Examples:
  00_Master_html_file      ← Output destination
  01_Administration        ← Source folder #1
  02_Projects              ← Source folder #2
  ...
  10_IFX_internal_trainings ← Source folder #10

Benefits:
  ✓ Alphabetically sorted
  ✓ Easy to reference
  ✓ Clear hierarchy
  ✓ Scalable system
```

---

**Legend**:
- `─▶` : Data flow / Reference
- `◄──` : Current location / Important note
- `✓` : Success / Working
- `❌` : Error / Not working
- `✅` : Fixed / Verified
