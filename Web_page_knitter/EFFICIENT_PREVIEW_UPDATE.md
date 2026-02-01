# Efficient Preview Implementation

## Problem Solved

Previously, the app copied entire report folders to `www/` for preview, which was:
- **Redundant**: Duplicated all assets unnecessarily
- **Inefficient**: Large folders took time to copy
- **Complex**: Required managing synchronized copies
- **Confusing**: Reports existed in multiple locations

## New Solution: `addResourcePath()`

Instead of copying files, we now use Shiny's built-in `addResourcePath()` to serve reports directly from their destination folders.

### How It Works

1. **Render Report**: Report is created in destination folder (e.g., `Web_page_knitter/Sample/Test.html`)
2. **Register Resource Path**: A unique URL prefix (e.g., `report_71369e54`) maps to the report directory
3. **Serve Directly**: Shiny serves files from original location via the registered path
4. **Preview**: iframe loads using the resource path URL

### Code Changes

#### Before (Inefficient):
```r
# Copy report + assets to www folder
iframe_src <- copy_report_to_www(
  report_path = report_filepath,
  source_folder = src_to_copy,
  www_folder = "www"
)
# iframe_src = "Sample/Test.html" (served from www/)
```

#### After (Efficient):
```r
# Register the destination folder as a servable resource
resource_prefix <- paste0("report_", uid)
report_dir <- dirname(report_filepath)
addResourcePath(resource_prefix, report_dir)

# Construct URL using the resource path
iframe_src_final <- paste0(resource_prefix, "/", basename(report_filepath))
# iframe_src_final = "report_71369e54/Test.html" (served from destination)
```

### Benefits

✅ **No Redundant Copying**: Assets stay in one place  
✅ **Faster**: Instant preview without file operations  
✅ **Cleaner**: Single source of truth for reports  
✅ **Memory Efficient**: No duplicated files  
✅ **Simpler**: Less code, fewer edge cases  

### Resource Cleanup

When a preview tab is closed:
```r
# Remove the resource path mapping
removeResourcePath(info$resource_prefix)
# Original report files remain untouched in destination folder
```

### Additional Fixes

1. **Double Slash Fix**: Added `clean_dest_path <- gsub("/$", "", section$destination_path)` to remove trailing slashes
2. **Path Consistency**: All paths now use forward slashes for cross-platform compatibility
3. **Absolute Path Resolution**: Resource paths are normalized to absolute paths for Shiny

## Technical Details

### Resource Path Registration
```r
addResourcePath(prefix, directoryPath)
```
- `prefix`: URL path component (must be unique)
- `directoryPath`: Absolute path to folder on disk
- Result: `http://127.0.0.1:PORT/prefix/file.html` serves `directoryPath/file.html`

### Unique Prefixes
Each report gets a unique prefix based on its UID:
```r
resource_prefix <- paste0("report_", uid)
# Example: "report_71369e54"
```

### Multiple Reports
Multiple reports can be open simultaneously, each with its own resource path:
- `report_71369e54` → `/workspaces/.../Sample/`
- `report_a1b2c3d4` → `/workspaces/.../Output/`
- `report_e5f6g7h8` → `/workspaces/.../Results/`

## Testing

To verify the fix works:
1. Render a report
2. Check console logs for:
   ```
   Report rendered successfully to: Web_page_knitter/Sample/Test.html
   Added resource path: report_71369e54 -> /workspaces/.../Sample
   DEBUG: iframe_src will be: 'report_71369e54/Test.html'
   ```
3. Verify report appears in preview tab
4. Verify `www/` folder is NOT populated with copies
5. Close tab and verify resource path is removed

## Migration Note

The `copy_report_to_www()` function remains in the code (unused) for backward compatibility. It can be safely removed if no other code depends on it.
