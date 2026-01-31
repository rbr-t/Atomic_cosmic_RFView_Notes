# Web-page-knitter Feature Update

## Updates Completed

### 1. Generic Templates Added ✅

The IFX integration module now includes **10 new generic templates** in addition to the original 10 IFX-specific templates:

#### Generic Templates:
1. **Meeting Notes** (`generic_meetings`) - For recording meeting minutes and action items
2. **Personal Projects** (`generic_projects`) - Personal project documentation
3. **Research Papers** (`generic_research`) - Academic research and paper organization
4. **Course Materials** (`generic_courses`) - Educational content and learning materials
5. **Documentation** (`generic_docs`) - Technical documentation and guides
6. **Portfolio** (`generic_portfolio`) - Portfolio showcase and project highlights
7. **Lab Notebooks** (`generic_lab`) - Laboratory research notes and experiments
8. **Book Notes** (`generic_books`) - Reading notes and book summaries
9. **Code Repository** (`generic_code`) - Code project documentation
10. **Client Work** (`generic_clients`) - Client project management and deliverables

#### Template Organization:
- Templates are now grouped in the UI for better organization:
  - 🏢 **IFX Templates** - Original 10 company-specific templates
  - 📚 **Generic Templates** - New 10 general-purpose templates

#### Path Structure:
- **IFX templates**: Follow original structure → `IFX_2022_2025/01_Administration/`
- **Generic templates**: Simplified structure → `Projects/Meeting_Notes/`, `Projects/Research_Papers/`, etc.

---

### 2. Interactive Notes/Questions Boxes ✅

Every embedded document now has an interactive notes box for active learning and document comprehension.

#### Features:
- **📝 Notes Input**: Collapsible textarea for recording questions and observations
- **💾 Save Notes**: Automatically saves notes to browser localStorage
- **🗑️ Clear Notes**: One-click clear with confirmation dialog
- **📥 Export Notes**: Export individual document notes as text file
- **🔄 Persistent Storage**: Notes survive page reloads (stored in browser)
- **🎨 Styled UI**: Purple gradient header, clean white textarea, colorful action buttons

#### Supported File Types:
Notes boxes appear next to ALL embedded file types:
- Images (PNG, JPG, GIF, BMP)
- Tables (CSV, XLSX, TXT)
- PDF documents
- HTML files
- Word documents (DOCX)
- Video files (MP4, WEBM, OGG, 3GP, FLV, MKV)
- Audio files (MP3, WAV, OGA, OGG)
- Archives (ZIP, TAR, GZ)
- Markdown (MD)
- R code (R, Rmd)
- JSON files
- XML files
- Email files (EML, MSG)
- PowerPoint presentations (PPTX, PPT)
- Default/unknown file types

#### JavaScript Functions:
- `saveNotes(docId)` - Save notes to localStorage
- `loadNotes(docId)` - Load notes from localStorage
- `clearNotes(docId)` - Clear notes with confirmation
- `exportNotes(docId, docName)` - Export notes as .txt file
- `toggleNotes(docId)` - Collapse/expand notes box
- `loadAllNotes()` - Auto-load all saved notes on page load

---

## Files Modified

### 1. `/Web_page_knitter/Modules/ifx_integration.R`
- **Lines 13-36**: Added generic templates to selectInput choices
- **Lines 110-165**: Updated server logic to handle both IFX and generic templates
  - Detects `generic_` prefix
  - Constructs appropriate paths for generic vs IFX templates
  - Uses human-friendly titles for generic templates

### 2. `/Web_page_knitter/Report_generator_ShinyApp.Rmd`
- **Lines 30-96**: Added `create_notes_box()` helper function and digest library
- **Lines 134-490**: Updated ALL file type handlers to include notes boxes
- **Lines 520-630**: Added JavaScript functions for notes management
  - Save/load from localStorage
  - Export functionality
  - Toggle visibility
  - Clear with confirmation

---

## Usage Instructions

### Using Generic Templates:

1. **Open the app**: Navigate to http://localhost:8081 (or your configured port)
2. **Select "IFX Integration" tab** in the left sidebar
3. **Choose a generic template** from the dropdown (under 📚 Generic Templates section)
4. **Specify base path**: e.g., `/workspaces/YourWorkspace/Projects/`
5. **Enter author name** and select format
6. **Click "Apply Template"** - Section will be auto-populated
7. **Render the report** to see your document with notes boxes

### Using Notes Boxes:

1. **Render a report** containing documents
2. **Locate the purple notes box** below each embedded document
3. **Click the header** to expand/collapse the notes area
4. **Type your questions/observations** in the textarea
5. **Notes save automatically** as you type or click "💾 Save Notes"
6. **Export notes** by clicking "📥 Export Notes" (downloads .txt file)
7. **Clear notes** by clicking "🗑️ Clear Notes" (requires confirmation)
8. **Notes persist** across page reloads (stored in browser localStorage)

---

## Technical Details

### Notes Storage:
- **Storage mechanism**: Browser localStorage API
- **Key format**: `doc-notes-{MD5_hash}`
- **Hash generation**: MD5 hash of file path (using digest package)
- **Persistence**: Survives browser refresh, lost if localStorage is cleared

### Template Detection Logic:
```r
is_generic <- grepl("^generic_", template_folder)

if (is_generic) {
  # Simplified path structure
  source_path <- file.path(base_path, display_name)
  destination_path <- file.path(base_path, "Reports")
  title <- paste(display_name, format(Sys.Date(), "%Y"))
} else {
  # Original IFX structure
  source_path <- file.path(base_path, template_folder)
  destination_path <- file.path(base_path, "00_Master_html_file")
  title <- paste("IFX", display_name, "2022-2026")
}
```

### Notes Box HTML Structure:
```html
<div class="document-notes-container">
  <div class="notes-header" onclick="toggleNotes('doc_id')">
    📝 Questions & Observations for: [Document Name]
  </div>
  <div id="notes-content-doc_id" class="notes-content">
    <textarea id="notes-textarea-doc_id"></textarea>
    <button onclick="saveNotes('doc_id')">💾 Save Notes</button>
    <button onclick="clearNotes('doc_id')">🗑️ Clear Notes</button>
    <button onclick="exportNotes('doc_id', 'name')">📥 Export Notes</button>
  </div>
</div>
```

---

## Testing Recommendations

1. **Test generic templates**:
   - Select each generic template type
   - Verify correct path construction
   - Check title formatting

2. **Test notes functionality**:
   - Add notes to multiple documents
   - Reload page and verify persistence
   - Export notes and check file contents
   - Clear notes and confirm deletion
   - Toggle collapse/expand

3. **Test different file types**:
   - Embed various file types (PDF, images, tables, etc.)
   - Verify notes box appears for each
   - Test save/load across different document types

---

## Known Limitations

1. **Notes storage**: Limited by browser localStorage quota (~5-10 MB)
2. **Notes persistence**: Lost if user clears browser data
3. **No server-side storage**: Notes are client-side only
4. **No multi-device sync**: Notes don't sync across browsers/devices

---

## Future Enhancement Ideas

1. **Server-side notes storage**: Save notes to JSON files on server
2. **Export all notes**: Button to export all document notes as single file
3. **Search notes**: Search functionality across all saved notes
4. **Notes statistics**: Word count, character count, last modified timestamp
5. **Markdown support**: Allow markdown formatting in notes
6. **Tagging system**: Add tags/categories to notes for organization
7. **Sharing**: Share notes with other users
8. **Version history**: Track changes to notes over time

---

## Changelog

**Version 2.1.0** - [Current Date]
- ✅ Added 10 generic templates for broader use cases
- ✅ Implemented interactive notes/questions boxes for all document types
- ✅ Added localStorage persistence for notes
- ✅ Added export functionality for individual notes
- ✅ Enhanced UI with collapsible notes panels
- ✅ Updated server logic to handle generic template paths

**Version 2.0.0** - [Previous Date]
- Original IFX-specific implementation with 10 templates
- Document embedding for 10+ file types
- Hierarchical folder processing
- RMarkdown report generation

---

## Support

For issues or questions:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)
3. Refer to [Web_Page_Knitter_Architecture_Documentation.html](Web_Page_Knitter_Architecture_Documentation.html)

---

*Last updated: [Current Date]*
*App running on: http://0.0.0.0:8081*
