# Web-page-knitter: New Features Guide

*Last Updated: January 2025*

## Overview

This guide covers all the new features added to the Web-page-knitter application, inspired by real-world usage with the IFX_2022_2025 folder structure.

---

## Table of Contents

1. [Enhanced Path Handling](#1-enhanced-path-handling)
2. [Path Validation](#2-path-validation)
3. [Recent Paths](#3-recent-paths)
4. [Improved Error Messages](#4-improved-error-messages)
5. [Example Configurations](#5-example-configurations)
6. [Path Testing](#6-path-testing)
7. [IFX Integration Module](#7-ifx-integration-module)
8. [Batch Operations](#8-batch-operations)
9. [Progress Indicators](#9-progress-indicators)

---

## 1. Enhanced Path Handling

### What's New?

The app now intelligently handles various path formats:

- **Relative paths**: `IFX_2022_2025/01_Administration/`
- **Absolute paths**: `/workspaces/project/IFX_2022_2025/...`
- **Windows paths**: `C:/Users/username/...`
- **iShare URLs**: `https://apps.eu.valeo.com/ishare/...`
- **Tilde paths**: `~/Documents/project/`

### How It Works

```r
# Automatically converts any path format to usable path
normalize_path_for_app("C:/Users/me/project/")
# Returns: "/workspaces/project/" (if that's your workspace)

normalize_path_for_app("IFX_2022_2025/01_Administration/")
# Returns: "/workspaces/Atomic_cosmic_RFView_Notes/IFX_2022_2025/01_Administration/"
```

### Best Practice

✅ **Use relative paths** for portability:
```
Source: IFX_2022_2025/01_Administration/
Destination: IFX_2022_2025/00_Master_html_file/
```

This works across:
- Different computers
- Different operating systems
- Different workspace locations
- Version control systems

---

## 2. Path Validation

### What's New?

Before rendering, the app validates:
- Source folder exists
- Source folder is readable
- Source folder contains files
- Destination folder is writable
- Paths don't contain invalid characters

### Error Categories

**Non-existent Path**
```
✗ Source path does not exist: IFX_2022_2025/99_NotFound/
Suggestion: Check for typos. Available folders: 01_Administration, 02_Projects, ...
```

**Permission Error**
```
✗ Source path exists but is not readable: /root/restricted/
Suggestion: Check folder permissions. Try running: chmod +r /root/restricted/
```

**Empty Folder**
```
⚠ Source folder is empty: IFX_2022_2025/01_Administration/
Suggestion: Ensure the folder contains files before rendering.
```

### Manual Validation

Use the **"Test All Paths"** button to validate before rendering:

```
[Button: Test All Paths]
```

This shows a modal with detailed results for each section.

---

## 3. Recent Paths

### What's New?

The app now remembers your last 10 source and destination paths.

### How to Use

1. **Select from dropdown**: Choose a recently used path
2. **Auto-populate**: The text input fills automatically
3. **Edit if needed**: Modify the auto-filled path

### UI Location

When adding a section:
```
┌─────────────────────────────────────┐
│ Recent Source Paths:                │
│ ▼ IFX_2022_2025/01_Administration/  │
├─────────────────────────────────────┤
│ Source Folder                        │
│ [IFX_2022_2025/01_Administration/]  │ ← Auto-filled!
└─────────────────────────────────────┘
```

### Storage

- Stored in: `www/recent_paths.json`
- Persists across sessions
- Saves only successful paths (after render succeeds)

---

## 4. Improved Error Messages

### What's New?

Errors now include:
- **Context**: What section failed
- **Cause**: Why it failed
- **Suggestion**: How to fix it

### Example Error Messages

**Before**:
```
Error rendering section_1
```

**After**:
```
Invalid source path for 'IFX Administration 2022-2026':
Source path does not exist: IFX_2022_2025/01_Admin/

Suggestion: Check for typos. Did you mean:
  - IFX_2022_2025/01_Administration/
  - IFX_2022_2025/02_Projects/
```

---

## 5. Example Configurations

### What's New?

Click **"Show Examples"** to see real-world configurations based on IFX folder structure.

### Example 1: Administration Report

```yaml
Source: IFX_2022_2025/01_Administration/
Destination: IFX_2022_2025/00_Master_html_file/
Title: IFX Administration 2022-2026
Author: Your Name
```

### Example 2: Master Dashboard

```yaml
Source: IFX_2022_2025/Report_generator_rmd/
Destination: IFX_2022_2025/00_Master_html_file/
Title: My Activity Summary
Author: Your Name
Format: HTML Document
```

### Example 3: Business Trips

```yaml
Source: IFX_2022_2025/06_Business_Trips/
Destination: IFX_2022_2025/00_Master_html_file/
Title: IFX Business Trips 2022-2026
Author: Your Name
```

### General Tips

The examples modal includes:
- ✅ Use relative paths for portability
- ✅ Use numbered prefixes (01_, 02_) for ordering
- ✅ Keep source files organized hierarchically
- ✅ Save profiles for repeated workflows
- ✅ Use IFX Integration panel for quick setup

---

## 6. Path Testing

### What's New?

Test all paths before rendering to catch errors early.

### How to Use

1. Click **"Test All Paths"** button
2. Review the modal with results for each section
3. Fix any issues before rendering

### Test Results Modal

```
┌────────────────────────────────────────────┐
│ Path Test Results                          │
├────────────────────────────────────────────┤
│ ✓ All paths are valid! You can proceed   │
│   with rendering.                          │
├────────────────────────────────────────────┤
│ ✓ IFX Administration 2022-2026            │
│   Section: section_1                       │
│   ✓ Source: IFX_2022_2025/01_Admin...    │
│   ✓ Destination: IFX_2022_2025/00_...   │
│   ✓ Logo: valeo_logo.png                 │
├────────────────────────────────────────────┤
│ ✗ IFX Projects Report                      │
│   Section: section_2                       │
│   ✗ Source: IFX_2022_2025/99_Wrong/      │
│   ✓ Destination: IFX_2022_2025/00_...   │
│   ✓ Logo: valeo_logo.png                 │
└────────────────────────────────────────────┘
```

---

## 7. IFX Integration Module

### What's New?

Quick-setup panel with pre-configured templates for all IFX folder types.

### How to Enable

1. Check **"☑ Show IFX Integration"** in the left sidebar
2. Purple panel appears with templates

### Available Templates

| Template | Folder Type | Output |
|----------|-------------|---------|
| Administration | 01_Administration | HR, contracts, salary |
| Projects | 02_Projects | Project reports |
| PRD | 03_PRD | Performance reviews |
| Conferences | 04_Conferences | Conference materials |
| Study Material | 05_Study_Material | Training docs |
| Business Trips | 06_Business_Trips | Travel reports |
| Technical Reports | 07_Technical_reports | Technical docs |
| Competition | 08_Competition | Market analysis |
| Presentations | 09_My_presentations | Presentations |
| Trainings | 10_IFX_internal_trainings | Training materials |

### How to Use

1. Click a template button (e.g., **"Administration"**)
2. A new section is created with:
   - ✅ Source path pre-filled
   - ✅ Destination pre-filled
   - ✅ Title pre-filled
   - ✅ Author pre-filled
   - ✅ Format pre-selected
3. Edit if needed, then click **"Render Reports"**

### Example Workflow

```
1. ☑ Show IFX Integration
2. Click [Administration] button
3. Section appears with:
   Source: IFX_2022_2025/01_Administration/
   Destination: IFX_2022_2025/00_Master_html_file/
   Title: IFX Administration 2022-2026
   Author: Your Name
4. Click [Render Reports]
5. Done! ✓
```

---

## 8. Batch Operations

### What's New?

Quickly select or deselect all sections at once.

### Buttons

- **"Select All"**: Check all section checkboxes
- **"Deselect All"**: Uncheck all section checkboxes

### Use Cases

**Selective Rendering**:
```
1. Click [Deselect All]
2. Manually check sections 1, 3, 5
3. Click [Render Reports]
4. Only checked sections render
```

**Quick Enable**:
```
1. Click [Select All]
2. Click [Render Reports]
3. All sections render
```

### Notifications

```
✓ Selected 8 section(s)
✗ Deselected 8 section(s)
```

---

## 9. Progress Indicators

### What's New?

Real-time progress during rendering with section counts.

### Progress Display

```
┌────────────────────────────────────┐
│ Rendering reports...               │
├────────────────────────────────────┤
│ [████████░░░░░░░░] 50%            │
│ [3/6] Rendering: IFX Business...  │
└────────────────────────────────────┘
```

### Information Shown

- **Current section**: `[3/6]`
- **Section title**: `Rendering: IFX Business Trips...`
- **Overall progress**: Visual bar + percentage
- **Incremental updates**: After each section completes

### Performance

- **No blocking**: UI remains responsive
- **Skip unchecked**: Only renders selected sections
- **Accurate count**: Shows checked sections only

---

## Quick Reference Card

### Most Common Workflow

```
┌─────────────────────────────────────────────┐
│ 1. ☑ Show IFX Integration                  │
│ 2. Click [Administration]                   │
│ 3. Click [Projects]                         │
│ 4. Click [Business Trips]                   │
│ 5. Click [Test All Paths]                   │
│ 6. Review modal, fix any issues             │
│ 7. Click [Render Reports]                   │
│ 8. Watch progress: [2/3] Rendering...      │
│ 9. Done! Open rendered HTML files           │
└─────────────────────────────────────────────┘
```

### Keyboard Shortcuts

None currently implemented. Consider adding:
- `Ctrl+Enter`: Render Reports
- `Ctrl+T`: Test All Paths
- `Ctrl+A`: Add Section
- `Ctrl+Shift+A`: Select All
- `Ctrl+Shift+D`: Deselect All

---

## Troubleshooting

### Problem: Recent paths not saving

**Solution**: Check file permissions for `www/recent_paths.json`

```bash
ls -la Web-page-knitter/www/recent_paths.json
chmod 644 Web-page-knitter/www/recent_paths.json
```

### Problem: IFX Integration not appearing

**Solution**: Ensure module file exists and is sourced

```r
# Check if file exists
file.exists("Web-page-knitter/Modules/ifx_integration.R")

# Should print: IFX integration module loaded successfully
```

### Problem: Path validation errors

**Solution**: Use absolute path temporarily, then switch to relative

```
Step 1: Use absolute path
/workspaces/Atomic_cosmic_RFView_Notes/IFX_2022_2025/01_Administration/

Step 2: Test and verify it works

Step 3: Switch to relative
IFX_2022_2025/01_Administration/
```

### Problem: Progress bar not updating

**Solution**: This is normal for long renders. The bar updates between sections, not during individual section rendering.

---

## Migration Guide

### For Existing Users

#### Before (Old Workflow)

```
1. Manually type paths
2. Make typos
3. Render fails
4. Fix typo
5. Render again
6. Repeat for each section
```

#### After (New Workflow)

```
1. Click [Show Examples]
2. Copy example paths
3. Click [Test All Paths]
4. All validated at once
5. Click [Render Reports]
6. Progress shown automatically
```

### Converting Old Profiles

If you have saved profiles with absolute paths:

1. Load the profile
2. Edit each section to use relative paths
3. Save as a new profile with `_portable` suffix
4. Delete old profile
5. Rename new profile

Example:
```
Old: my-work-profile → my-work-profile_portable → my-work-profile
```

---

## Advanced Features

### Custom Path Validation

Add custom validation rules in `app.R`:

```r
validate_source_path <- function(path) {
  # Add your custom checks here
  if (grepl("forbidden", path)) {
    return(list(
      valid = FALSE,
      error = "Forbidden folder name",
      suggestion = "Use a different folder name"
    ))
  }
  # ... existing code ...
}
```

### Custom Recent Paths Limit

Change the limit in `get_recent_paths()`:

```r
# Default: 10
recent <- tail(unique(paths), 10)

# Increase to 20
recent <- tail(unique(paths), 20)
```

### Custom IFX Templates

Add more templates in `ifx_integration.R`:

```r
list(
  id = "my_custom",
  label = "My Custom Template",
  icon = "star",
  config = list(
    source = "IFX_2022_2025/99_Custom/",
    destination = "IFX_2022_2025/00_Master_html_file/",
    title = "My Custom Report",
    author = "Your Name",
    format = "rmarkdown::html_document"
  )
)
```

---

## FAQ

**Q: Do I need to update my .Rmd files?**  
A: No, the app handles path conversion automatically.

**Q: Will my old profiles still work?**  
A: Yes, but you should update them to use relative paths for portability.

**Q: Can I disable recent paths tracking?**  
A: Not currently, but you can delete `www/recent_paths.json` to clear history.

**Q: How many sections can I render at once?**  
A: No limit, but rendering time increases linearly. Use "Deselect All" + manual selection for large numbers.

**Q: Can I customize the IFX templates?**  
A: Yes, edit `Modules/ifx_integration.R` and add your own templates.

**Q: Does path validation slow down the app?**  
A: No, validation only runs when you click "Test All Paths" or start rendering.

---

## What's Next?

Planned features for future releases:

- [ ] Keyboard shortcuts
- [ ] Drag-and-drop section reordering
- [ ] Export/import sections as JSON
- [ ] Template marketplace
- [ ] Multi-language support
- [ ] Dark mode
- [ ] Render queue (pause/resume)
- [ ] Email notifications when render completes
- [ ] Cloud sync for profiles

---

## Support

For issues or questions:

1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Check [RECOMMENDATIONS.md](RECOMMENDATIONS.md)
3. Check app console for error messages
4. Review this guide's "Troubleshooting" section

---

## Version History

### v2.0.0 (January 2025)
- ✨ Enhanced path handling (relative, absolute, Windows, iShare)
- ✨ Path validation with detailed errors
- ✨ Recent paths tracking
- ✨ Example configurations modal
- ✨ Path testing before render
- ✨ IFX Integration module
- ✨ Batch operations (select/deselect all)
- ✨ Enhanced progress indicators

### v1.0.0 (Previous)
- Basic report generation
- Profile save/load
- Multiple report formats
- Master/individual report modes

---

*End of Guide*
