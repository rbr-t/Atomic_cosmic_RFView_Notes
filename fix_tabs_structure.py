#!/usr/bin/env python3
"""
Fix all heading levels to match the specified tab structure.
"""

import re

# Define the correct structure - which h2 headings should exist as tabs
CORRECT_TABS = {
    'Atomic & Quantum Level': [
        'Introduction to Quantum RF',
        'Quantum Properties', 
        'Atomic Interactions',
        'References & Resources'
    ],
    'Molecular & Material Level': [
        'Material Properties',
        'Substrate Materials',
        'Conductors & Semiconductors',
        'Crystal Structures'
    ],
    'Device Level': [
        'Passive Components',
        'Active Components',
        'Transmission Lines',
        'Antennas',
        'Filters & Matching'
    ],
    'System Level': [
        'RF Systems',
        'Modulation Schemes',
        'Communication Standards',
        'Radar Systems',
        'System Performance'
    ],
    'Terrestrial Level': [
        'Network Infrastructure',
        'Propagation Models',
        'Spectrum Management',
        'Backhaul & Distribution',
        'Smart Cities & IoT'
    ],
    'Cosmic Level': [
        'Space Communications',
        'Radio Astronomy',
        'Navigation Systems',
        'Cosmic Radio Sources',
        'Future of RF Technology'
    ]
}

def fix_structure(content):
    lines = content.split('\n')
    result = []
    current_main_topic = None
    current_tabs = None
    
    for i, line in enumerate(lines):
        # Detect main topic (h1 with .tabset)
        h1_match = re.match(r'^# (🔬|🧬|💾|📡|🌍|🚀) (.+?) \{\.tabset', line)
        if h1_match:
            emoji, topic = h1_match.groups()
            # Map topic name
            for key in CORRECT_TABS:
                if any(word in topic for word in key.split()):
                    current_main_topic = key
                    current_tabs = CORRECT_TABS[key]
                    break
            result.append(line)
            continue
        
        # Check for new h1 without tabset (end of tabset section)
        if re.match(r'^# [^#]', line) and '{.tabset' not in line:
            current_main_topic = None
            current_tabs = None
            result.append(line)
            continue
        
        # Inside a tabset section
        if current_main_topic and current_tabs:
            # Check if this is an h2 or h3
            h2_match = re.match(r'^## ([^#].+?)$', line)
            h3_match = re.match(r'^### ([^#].+?)$', line)
            h4_match = re.match(r'^#### ([^#].+?)$', line)
            
            if h2_match:
                title = h2_match.group(1).strip()
                # Check if this should be a tab
                if title in current_tabs:
                    # Keep as h2 (tab)
                    result.append(line)
                else:
                    # Demote to h3 (chapter)
                    result.append('###' + line[2:])
                continue
            
            if h3_match:
                title = h3_match.group(1).strip()
                # Check if this should be a tab
                if title in current_tabs:
                    # Promote to h2 (tab)
                    result.append('##' + line[3:])
                else:
                    # Keep as h3 (chapter)
                    result.append(line)
                continue
            
            if h4_match:
                title = h4_match.group(1).strip()
                # Check if this should be a tab
                if title in current_tabs:
                    # Promote to h2 (tab)
                    result.append('##' + line[4:])
                else:
                    # Keep as h4 (sub-chapter)
                    result.append(line)
                continue
        
        # Default: keep line as is
        result.append(line)
    
    return '\n'.join(result)

def main():
    input_file = 'Atomic_Cosmic_RFView.Rmd'
    
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    fixed_content = fix_structure(content)
    
    # Add About section if not present
    if '# About' not in fixed_content:
        fixed_content += '\n\n# About\n\n**Atomic to Cosmic RF View**\n\nThis interactive document provides a comprehensive journey through RF engineering, spanning from quantum-level atomic interactions to cosmic-scale radio phenomena.\n\n**Author Information:**\n\nCreated as an educational resource for RF engineers, students, and researchers.\n\n**Technical Requirements:**\n\n- Modern web browser with JavaScript enabled\n- Interactive visualizations powered by R and ggplot2\n- Mathematical equations rendered with MathJax\n\n**License & Usage:**\n\nThis material is provided for educational purposes. Please cite appropriately when referencing.\n'
    
    with open(input_file, 'w', encoding='utf-8') as f:
        f.write(fixed_content)
    
    print(f"Fixed structure in {input_file}")
    
    # Show summary
    original_h2 = len(re.findall(r'^## ', content, re.MULTILINE))
    original_h3 = len(re.findall(r'^### ', content, re.MULTILINE))
    
    fixed_h2 = len(re.findall(r'^## ', fixed_content, re.MULTILINE))
    fixed_h3 = len(re.findall(r'^### ', fixed_content, re.MULTILINE))
    
    print(f"\nOriginal: {original_h2} h2, {original_h3} h3")
    print(f"Fixed: {fixed_h2} h2, {fixed_h3} h3")
    print(f"Changes: {fixed_h2-original_h2:+d} h2, {fixed_h3-original_h3:+d} h3")

if __name__ == '__main__':
    main()
