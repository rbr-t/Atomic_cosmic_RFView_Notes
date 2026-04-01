#!/usr/bin/env python3
"""
Script to fix hardcoded Windows paths in IFX .Rmd files to use relative paths.
This makes the files portable across different systems and locations.

Usage:
    python fix_ifx_paths.py [--dry-run] [--no-backup]
    
Options:
    --dry-run: Show what would be changed without actually modifying files
    --no-backup: Don't create backup files (use with caution)
"""

import os
import re
import shutil
import argparse
from pathlib import Path
from datetime import datetime

# Path mappings: Old Windows path -> New relative path (from Report_generator_rmd)
PATH_MAPPINGS = {
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/00_Master_html_file': '../00_Master_html_file',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/01_Administration/': '../01_Administration/',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/02_Projects/': '../02_Projects/',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/03_PRD/': '../03_PRD/',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/04_Conferences/': '../04_Conferences/',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/05_Study_Material/': '../05_Study_Material/',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/06_Business_Trips/': '../06_Business_Trips/',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/07_Technical_reports/': '../07_Technical_reports/',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/08_Competition/': '../08_Competition/',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/09_My_presentations': '../09_My_presentations',
    r'C:/Users/talluribhaga/Documents/My_IFX_activity/10_IFX_internal_trainings/': '../10_IFX_internal_trainings/',
}

class PathFixer:
    def __init__(self, rmd_dir, dry_run=False, create_backup=True):
        self.rmd_dir = Path(rmd_dir)
        self.dry_run = dry_run
        self.create_backup = create_backup
        self.changes_log = []
        self.files_processed = 0
        self.files_modified = 0
        
    def fix_file(self, filepath):
        """Fix paths in a single .Rmd file."""
        print(f"\n{'[DRY RUN] ' if self.dry_run else ''}Processing: {filepath.name}")
        
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        changes_in_file = []
        
        # Apply each path mapping
        for old_path, new_path in PATH_MAPPINGS.items():
            # Escape special regex characters in the old path
            old_path_escaped = re.escape(old_path)
            
            # Find all occurrences
            pattern = re.compile(old_path_escaped, re.IGNORECASE)
            matches = pattern.findall(content)
            
            if matches:
                count = len(matches)
                content = pattern.sub(new_path, content)
                change_msg = f"  ✓ Replaced '{old_path}' -> '{new_path}' ({count} occurrence{'s' if count > 1 else ''})"
                print(change_msg)
                changes_in_file.append(change_msg)
        
        # Check if any changes were made
        if content != original_content:
            self.files_modified += 1
            self.changes_log.extend([(filepath.name, change) for change in changes_in_file])
            
            if not self.dry_run:
                # Create backup if requested
                if self.create_backup:
                    backup_path = filepath.with_suffix(filepath.suffix + '.backup')
                    shutil.copy2(filepath, backup_path)
                    print(f"  ℹ Backup created: {backup_path.name}")
                
                # Write the modified content
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"  ✓ File updated successfully")
            else:
                print(f"  [DRY RUN] Would update file")
        else:
            print(f"  ℹ No changes needed")
        
        self.files_processed += 1
        
    def fix_all_files(self):
        """Fix paths in all .Rmd files in the directory."""
        rmd_files = list(self.rmd_dir.glob('*.Rmd'))
        
        if not rmd_files:
            print(f"No .Rmd files found in {self.rmd_dir}")
            return
        
        print(f"{'='*70}")
        print(f"IFX Path Fixer - {'DRY RUN MODE' if self.dry_run else 'LIVE MODE'}")
        print(f"{'='*70}")
        print(f"Found {len(rmd_files)} .Rmd file(s) to process")
        print(f"Backup: {'Enabled' if self.create_backup else 'Disabled'}")
        
        for rmd_file in sorted(rmd_files):
            self.fix_file(rmd_file)
        
        self.print_summary()
    
    def print_summary(self):
        """Print a summary of all changes made."""
        print(f"\n{'='*70}")
        print("SUMMARY")
        print(f"{'='*70}")
        print(f"Files processed: {self.files_processed}")
        print(f"Files modified: {self.files_modified}")
        print(f"Files unchanged: {self.files_processed - self.files_modified}")
        
        if self.changes_log:
            print(f"\nDetailed changes:")
            current_file = None
            for filename, change in self.changes_log:
                if filename != current_file:
                    print(f"\n{filename}:")
                    current_file = filename
                print(f"  {change}")
        
        if self.dry_run:
            print(f"\n⚠ This was a DRY RUN. No files were actually modified.")
            print(f"Run without --dry-run to apply changes.")
        else:
            print(f"\n✓ All changes have been applied.")
            if self.create_backup:
                print(f"✓ Backup files created (*.Rmd.backup)")
                print(f"  You can delete them once you verify the changes.")
        
        print(f"{'='*70}\n")

def main():
    parser = argparse.ArgumentParser(
        description='Fix hardcoded Windows paths in IFX .Rmd files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Preview changes without modifying files
  python fix_ifx_paths.py --dry-run
  
  # Apply changes and create backups
  python fix_ifx_paths.py
  
  # Apply changes without creating backups
  python fix_ifx_paths.py --no-backup
        """
    )
    
    parser.add_argument('--dry-run', action='store_true',
                       help='Show what would be changed without modifying files')
    parser.add_argument('--no-backup', action='store_true',
                       help="Don't create backup files")
    
    args = parser.parse_args()
    
    # Get the script directory and locate Report_generator_rmd
    script_dir = Path(__file__).parent
    rmd_dir = script_dir / 'Report_generator_rmd'
    
    if not rmd_dir.exists():
        print(f"Error: Directory not found: {rmd_dir}")
        print("Make sure this script is in the IFX_2022_2025 directory")
        return 1
    
    # Create the path fixer and run it
    fixer = PathFixer(
        rmd_dir=rmd_dir,
        dry_run=args.dry_run,
        create_backup=not args.no_backup
    )
    
    fixer.fix_all_files()
    
    return 0

if __name__ == '__main__':
    exit(main())
