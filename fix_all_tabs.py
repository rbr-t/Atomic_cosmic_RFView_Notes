#!/usr/bin/env python3
"""
Fix tab structure in Atomic_Cosmic_RFView.Rmd
Ensures h2 (##) headings match the user-specified tab names for each main topic.
"""

import re

# Define the correct tab structure for each main topic
MAIN_TOPICS = {
    "Atomic & Quantum Level": {
        "tabs": [
            "Introduction to Quantum RF",
            "Quantum Properties",
            "Atomic Interactions",
            "References & Resources"
        ]
    },
    "Molecular & Material Level": {
        "tabs": [
            "Material Properties",
            "Substrate Materials",
            "Conductors & Semiconductors",
            "Crystal Structures"
        ]
    },
    "Device Level": {
        "tabs": [
            "Passive Components",
            "Active Components",
            "Transmission Lines",
            "Antennas",
            "Filters & Matching"
        ]
    },
    "System Level": {
        "tabs": [
            "RF Systems",
            "Modulation Schemes",
            "Communication Standards",
            "Radar Systems",
            "System Performance"
        ]
    },
    "Terrestrial Level": {
        "tabs": [
            "Network Infrastructure",
            "Propagation Models",
            "Spectrum Management",
            "Backhaul & Distribution",
            "Smart Cities & IOT"
        ]
    },
    "Cosmic Level": {
        "tabs": [
            "Space Communications",
            "Radio Astronomy",
            "Navigation Systems",
            "Cosmic Radio Sources",
            "Future of RF Technology"
        ]
    }
}

def normalize_title(title):
    """Normalize title for comparison by removing special chars and extra spaces."""
    # Remove emojis and special characters
    title = re.sub(r'[🔬🧬💾📡🌍🚀]', '', title)
    # Remove {.tabset} and similar markers
    title = re.sub(r'\{[^}]*\}', '', title)
    # Normalize whitespace
    title = ' '.join(title.split())
    return title.strip()

def find_best_match(heading_text, tab_list):
    """Find if heading text matches any tab in the list."""
    normalized_heading = normalize_title(heading_text).lower()
    for tab in tab_list:
        normalized_tab = normalize_title(tab).lower()
        # Check for exact match or if one contains the other
        if normalized_tab == normalized_heading or normalized_tab in normalized_heading or normalized_heading in normalized_tab:
            return tab
    return None

def fix_rmd_structure(input_file='Atomic_Cosmic_RFView.Rmd', output_file=None):
    """Fix the heading structure in the Rmd file."""
    if output_file is None:
        output_file = input_file
    
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    new_lines = []
    current_main_topic = None
    current_tabs = []
    changes_made = []
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # Check for main topic (h1 with .tabset)
        h1_match = re.match(r'^# (.+)\{\.tabset', line)
        if h1_match:
            h1_title = normalize_title(h1_match.group(1))
            # Find matching main topic
            current_main_topic = None
            current_tabs = []
            for topic_name, topic_info in MAIN_TOPICS.items():
                if normalize_title(topic_name).lower() in h1_title.lower() or h1_title.lower() in normalize_title(topic_name).lower():
                    current_main_topic = topic_name
                    current_tabs = topic_info['tabs']
                    print(f"Found main topic: {current_main_topic}")
                    break
            new_lines.append(line)
            i += 1
            continue
        
        # Check for h2, h3, h4 headings
        h2_match = re.match(r'^## (.+)$', line)
        h3_match = re.match(r'^### (.+)$', line)
        h4_match = re.match(r'^#### (.+)$', line)
        
        if current_main_topic and current_tabs:
            if h2_match:
                heading_text = h2_match.group(1).strip()
                matched_tab = find_best_match(heading_text, current_tabs)
                if matched_tab:
                    # This is a correct tab, keep as h2
                    new_lines.append(line)
                    print(f"  ✓ Kept h2: {heading_text}")
                else:
                    # This h2 is not a tab, demote to h3
                    new_line = f"### {heading_text}\n"
                    new_lines.append(new_line)
                    changes_made.append(f"  ✓ Demoted h2 → h3: {heading_text}")
                    print(f"  ✓ Demoted h2 → h3: {heading_text}")
                i += 1
                continue
            
            elif h3_match:
                heading_text = h3_match.group(1).strip()
                matched_tab = find_best_match(heading_text, current_tabs)
                if matched_tab:
                    # This should be a tab, promote to h2
                    new_line = f"## {heading_text}\n"
                    new_lines.append(new_line)
                    changes_made.append(f"  ✓ Promoted h3 → h2: {heading_text}")
                    print(f"  ✓ Promoted h3 → h2: {heading_text}")
                else:
                    # Keep as h3 (it's a chapter within a tab)
                    new_lines.append(line)
                i += 1
                continue
        
        # If not in a tabset section or no match found, keep line as is
        new_lines.append(line)
        i += 1
    
    # Write output
    with open(output_file, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    
    print(f"\n{'='*60}")
    print(f"Structure fixed in {output_file}")
    print(f"{'='*60}")
    if changes_made:
        print("\nChanges made:")
        for change in changes_made:
            print(change)
    else:
        print("\nNo changes needed - structure already correct!")
    
    return len(changes_made)

if __name__ == '__main__':
    changes = fix_rmd_structure()
    print(f"\nTotal changes: {changes}")
