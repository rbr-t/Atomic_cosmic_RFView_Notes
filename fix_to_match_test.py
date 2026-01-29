#!/usr/bin/env python3
"""
Fix RMarkdown structure to exactly match the test HTML structure.

Based on test HTML analysis:
- h1: Main topics (with .tabset)
- h2: Auto-generated "Column" (skip in Rmd)
- h3: Tab titles (Rmd: ##)
- h4: Chapters within tabs (Rmd: ###)  
- h5: Sub-chapters (Rmd: ####)

Specific fixes needed:
1. "What is an Atom?" should be ### (chapter), not ## (tab)
2. Many h4 items under "Atomic Interactions" should be ###
3. Same pattern in other main topics
"""

import re

def fix_structure(content):
    lines = content.split('\n')
    result = []
    in_tabset = False
    current_tab = None
    
    for i, line in enumerate(lines):
        # Check if we're starting a tabset section
        if re.match(r'^# [^#].*\{\.tabset', line):
            in_tabset = True
            result.append(line)
            continue
        
        # Check if we're leaving tabset section (new h1 without tabset)
        if re.match(r'^# [^#]', line) and not '{.tabset' in line:
            in_tabset = False
            current_tab = None
            result.append(line)
            continue
        
        if not in_tabset:
            result.append(line)
            continue
        
        # Inside tabset section - need to fix structure
        
        # h2 starting a new tab
        if re.match(r'^## [^#]', line):
            # Check if this should be a tab or a chapter
            # Tabs: "Introduction to...", "Material Properties", "Passive Components", etc.
            # Chapters: "What is an Atom?", specific technical topics
            
            # Get the text
            text = line[3:].strip()
            
            # Heuristic: if it's a question or very specific technical term, it's likely a chapter
            is_chapter = (
                '?' in text or  # Questions are chapters
                text in ['What is an Atom?', 'Skin Effect:**', 'Conductor Properties and Current Flow']  or
                (current_tab and not any(x in text.lower() for x in ['properties', 'components', 'systems', 'schemes', 'standards', 'structures', 'materials']))
            )
            
            if is_chapter and current_tab:
                # This should be a chapter (h3 = ###)
                result.append('###' + line[2:])
            else:
                # This is a real tab
                current_tab = text
                result.append(line)
            continue
        
        # h3 - could be chapter or sub-chapter depending on context
        if re.match(r'^### [^#]', line):
            text = line[4:].strip()
            
            # If we don't have a tab yet, something is wrong
            # But keep as is
            result.append(line)
            continue
        
        # h4 and below - check if should be promoted
        if re.match(r'^#### [^#]', line):
            # h4 directly under h2 (tab) should often be h3 (chapter)
            # Look back to see what we had
            has_h3_since_h2 = False
            for j in range(len(result) - 1, max(0, len(result) - 20), -1):
                if re.match(r'^### [^#]', result[j]):
                    has_h3_since_h2 = True
                    break
                if re.match(r'^## [^#]', result[j]):
                    break
            
            if not has_h3_since_h2:
                # No h3 between here and last h2, so this h4 should be h3
                result.append('###' + line[3:])
            else:
                result.append(line)
            continue
        
        # Everything else stays as is
        result.append(line)
    
    return '\n'.join(result)

def main():
    input_file = 'Atomic_Cosmic_RFView.Rmd'
    
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    fixed_content = fix_structure(content)
    
    with open(input_file, 'w', encoding='utf-8') as f:
        f.write(fixed_content)
    
    print(f"Fixed structure in {input_file}")
    
    # Show summary
    original_h2 = len(re.findall(r'^## ', content, re.MULTILINE))
    original_h3 = len(re.findall(r'^### ', content, re.MULTILINE))
    original_h4 = len(re.findall(r'^#### ', content, re.MULTILINE))
    
    fixed_h2 = len(re.findall(r'^## ', fixed_content, re.MULTILINE))
    fixed_h3 = len(re.findall(r'^### ', fixed_content, re.MULTILINE))
    fixed_h4 = len(re.findall(r'^#### ', fixed_content, re.MULTILINE))
    
    print(f"\nOriginal: {original_h2} h2, {original_h3} h3, {original_h4} h4")
    print(f"Fixed: {fixed_h2} h2, {fixed_h3} h3, {fixed_h4} h4")
    print(f"Changes: {fixed_h2-original_h2:+d} h2, {fixed_h3-original_h3:+d} h3, {fixed_h4-original_h4:+d} h4")

if __name__ == '__main__':
    main()
