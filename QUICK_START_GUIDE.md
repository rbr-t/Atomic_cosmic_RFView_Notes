# Quick Start Guide: New Features

## 🎯 Feature 1: Generic Templates

### What's New?
You can now use the Web-page-knitter for any type of document collection, not just IFX-specific content!

### How to Use:

1. **Open the app**: http://localhost:8082

2. **Navigate to IFX Integration** (left sidebar)

3. **Select a generic template**:
   ```
   📚 Generic Templates
   ├── Meeting Notes
   ├── Personal Projects
   ├── Research Papers
   ├── Course Materials
   ├── Documentation
   ├── Portfolio
   ├── Lab Notebooks
   ├── Book Notes
   ├── Code Repository
   └── Client Work
   ```

4. **Configure the template**:
   - **Base Folder Path**: Where your documents are stored
     - Example: `/workspaces/MyProject/Notes/`
   - **Author**: Your name
   - **Output Format**: HTML with or without TOC

5. **Click "Apply Template"** → Section auto-populated!

6. **Click "Render Report"** → Beautiful HTML report generated!

---

## 📝 Feature 2: Interactive Notes Boxes

### What's New?
Every document now has a notes/questions box for active learning!

### How to Use:

1. **Render any report** with embedded documents

2. **Find the purple notes box** below each document:
   ```
   ┌─────────────────────────────────────────────────┐
   │ 📝 Questions & Observations for: [Document]  ▼ │
   ├─────────────────────────────────────────────────┤
   │ Use this space to record questions, key         │
   │ observations, or summaries...                   │
   │                                                 │
   │ ┌─────────────────────────────────────────────┐ │
   │ │ [Your notes here...]                        │ │
   │ │                                             │ │
   │ └─────────────────────────────────────────────┘ │
   │                                                 │
   │ [💾 Save] [🗑️ Clear] [📥 Export]              │
   └─────────────────────────────────────────────────┘
   ```

3. **Type your notes** in the textarea

4. **Save your notes**:
   - Automatic save on change
   - Manual save with "💾 Save Notes" button
   - Confirmation message appears

5. **Manage your notes**:
   - **Toggle visibility**: Click header to collapse/expand
   - **Export**: Download as .txt file
   - **Clear**: Remove all notes (with confirmation)

6. **Notes persist**: Reload the page → notes are still there!

---

## 🎨 Use Cases

### Research Papers:
1. Select "Research Papers" template
2. Point to your papers folder
3. Render report
4. Use notes boxes to:
   - Record key findings
   - Note questions for further investigation
   - Summarize main contributions
   - Track citation information

### Meeting Notes:
1. Select "Meeting Notes" template
2. Point to your meetings folder
3. Render report with all meeting documents
4. Use notes boxes to:
   - Highlight action items
   - Note follow-up questions
   - Track decisions made
   - Reference related meetings

### Course Materials:
1. Select "Course Materials" template
2. Point to your course folder (lectures, assignments, etc.)
3. Render consolidated view
4. Use notes boxes to:
   - Document understanding
   - Note difficult concepts
   - Create study questions
   - Link related topics

### Lab Notebooks:
1. Select "Lab Notebooks" template
2. Point to your lab data folder
3. Render experiment documentation
4. Use notes boxes to:
   - Record observations
   - Note anomalies
   - Track hypotheses
   - Link experimental results

---

## 💡 Tips & Tricks

### Organizing Notes:
- **Be specific**: Include page numbers, section references
- **Use questions**: "Why does X happen?", "How does Y relate to Z?"
- **Summarize**: Write one-sentence summaries of key points
- **Connect ideas**: Reference other documents in your notes

### Exporting Notes:
- Export individual document notes for focused review
- File naming: `notes-[document-name]_[timestamp].txt`
- Use exported notes for:
  - Study guides
  - Literature reviews
  - Project documentation
  - Meeting preparation

### Keyboard Workflow:
1. Scroll to document
2. Click in notes textarea
3. Type your observations
4. Notes auto-save on blur
5. Move to next document

### Browser Storage:
- Notes stored in localStorage (~5-10 MB limit)
- Per-domain storage (not shared across domains)
- Survives browser restart
- Lost if you clear browser data

---

## 🔧 Troubleshooting

### Notes not saving?
- Check browser console (F12) for errors
- Verify localStorage is enabled in browser settings
- Try a different browser
- Check if storage quota exceeded

### Template not working?
- Verify base folder path exists
- Check folder permissions
- Ensure folder contains documents
- Review path format (use forward slashes)

### App not loading?
- Check if port is available
- Try different port: `port=8082`
- Restart R session
- Check for R package errors

---

## 📊 Comparison: IFX vs Generic Templates

| Feature | IFX Templates | Generic Templates |
|---------|---------------|-------------------|
| Use Case | Company-specific | General purpose |
| Path Structure | `IFX_2022_2025/01_Admin/` | `Projects/Meeting_Notes/` |
| Title Format | "IFX [Name] 2022-2026" | "[Name] [Year]" |
| Destination | `00_Master_html_file/` | `Reports/` |
| Count | 10 templates | 10 templates |

---

## 🚀 Next Steps

1. **Try a generic template** with your own documents
2. **Experiment with notes boxes** - add questions to a few documents
3. **Export your notes** to see the text format
4. **Combine multiple templates** in a single report
5. **Share feedback** on what works well

---

## 📚 Additional Resources

- [FEATURE_UPDATE.md](FEATURE_UPDATE.md) - Detailed technical documentation
- [Web_Page_Knitter_Architecture_Documentation.html](Web_Page_Knitter_Architecture_Documentation.html) - Full architecture guide
- [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) - Project overview
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions

---

**App Status**: ✅ Running on http://0.0.0.0:8082

**Version**: 2.1.0

**Last Updated**: [Current Session]
