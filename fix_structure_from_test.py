#!/usr/bin/env python3
"""
Fix the RMarkdown heading structure to match the test HTML structure.

Test HTML structure:
- h1: Main topic
- h2: "Column" (tabset marker - skip this)
- h3: Tab titles (subtopics)  
- h4: Content chapters within tabs
- h5+ preserved as is

Current Rmd structure:
- h1: Main topic {.tabset}
- h2: Subtopic (becomes tab)
- h3, h4, h5: Content - NEEDS FIXING

Target Rmd structure:
- h1: Main topic {.tabset}
- h2: Subtopic (becomes tab)
- h3: Chapter (first level content in tab)
- h4: Sub-chapter
- h5: Details
"""

import re
import sys

def fix_heading_structure(content):
    """Fix heading levels to match test HTML structure"""
    lines = content.split('\n')
    result = []
    in_tabset_section = False
    current_h1_has_tabset = False
    in_h2_section = False  # Track if we're inside an h2 (tab) section
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # Check if this is an h1 line with tabset
        if re.match(r'^# [^#].*\{\.tabset', line):
            in_tabset_section = True
            current_h1_has_tabset = True
            result.append(line)
            i += 1
            continue
        
        # Check if this is a new h1 line without tabset (end of tabset section)
        if re.match(r'^# [^#]', line) and not '{.tabset' in line:
            in_tabset_section = False
            current_h1_has_tabset = False
            in_h2_section = False
            result.append(line)
            i += 1
            continue
        
        # If we're in a tabset section
        if in_tabset_section and current_h1_has_tabset:
            # h2 becomes a tab - keep as is
            if re.match(r'^## [^#]', line):
                in_h2_section = True
                result.append(line)
                i += 1
                continue
            
            # If we're inside an h2 (tab) section, adjust headings
            if in_h2_section:
                # Current h2 subtitles should stay as h3 (if they're already h3)
                # Current h3 should stay as h3 (chapters)
                # Current h4 should become h3 (if they're actually chapter-level content)
                # But we need to be smarter - look at the context
                
                # If it's h3, it's probably meant to be a chapter heading - keep it
                if re.match(r'^### [^#]', line):
                    result.append(line)
                    i += 1
                    continue
                
                # If it's h4, it might be:
                # - A sub-chapter (keep as h4)
                # - OR it was meant to be a chapter (should be h3)
                # Looking at test HTML: h4 is used for actual chapters
                # So current h4 in our Rmd might need to become h3
                # But some h4 are truly sub-chapters
                
                # Let's use a heuristic: if the h4 follows directly after h2 (no h3),
                # it's probably meant to be a chapter and should become h3
                if re.match(r'^#### [^#]', line):
                    # Look back to see if there's been an h3 since last h2
                    has_h3_since_h2 = False
                    for j in range(len(result) - 1, -1, -1):
                        if re.match(r'^### [^#]', result[j]):
                            has_h3_since_h2 = True
                            break
                        if re.match(r'^## [^#]', result[j]):
                            break
                    
                    # If no h3 found between here and last h2, this h4 should be h3
                    if not has_h3_since_h2:
                        result.append(re.sub(r'^#### ', '### ', line))
                    else:
                        # There was an h3, so this h4 is truly a sub-chapter
                        result.append(line)
                    i += 1
                    continue
                
                # h5 stays as h4 or h5 depending on context
                if re.match(r'^##### [^#]', line):
                    result.append(line)
                    i += 1
                    continue
        
        # Default: keep line as is
        result.append(line)
        i += 1
    
    return '\n'.join(result)

def main():
    # Read the current Rmd file
    input_file = 'Atomic_Cosmic_RFView.Rmd'
    
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Fix the structure
    fixed_content = fix_heading_structure(content)
    
    # Write to output
    output_file = 'Atomic_Cosmic_RFView.Rmd'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(fixed_content)
    
    print(f"Fixed heading structure written to {output_file}")
    
    # Show summary of changes
    original_h3 = len(re.findall(r'^### ', content, re.MULTILINE))
    original_h4 = len(re.findall(r'^#### ', content, re.MULTILINE))
    fixed_h3 = len(re.findall(r'^### ', fixed_content, re.MULTILINE))
    fixed_h4 = len(re.findall(r'^#### ', fixed_content, re.MULTILINE))
    
    print(f"\nOriginal: {original_h3} h3, {original_h4} h4")
    print(f"Fixed: {fixed_h3} h3, {fixed_h4} h4")
    print(f"Changes: {fixed_h3 - original_h3:+d} h3, {fixed_h4 - original_h4:+d} h4")

if __name__ == '__main__':
    main()
