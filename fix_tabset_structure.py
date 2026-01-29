#!/usr/bin/env python3
"""
Fix heading structure for proper tabset display:
After each h1 with {.tabset}, the next-level headings (currently h3) should be h2 for tabs to work.
Then chapters under those should be h3, etc.
"""

import re

with open('Atomic_Cosmic_RFView.Rmd', 'r', encoding='utf-8') as f:
    lines = f.readlines()

output = []
in_tabset = False
first_section_after_tabset = True

for i, line in enumerate(lines):
    # Check if this is an h1 with tabset
    if re.match(r'^# .*\{\.tabset', line):
        in_tabset = True
        first_section_after_tabset = True
        output.append(line)
        continue
    
    # Check if we hit a new h1 (end of tabset section)
    if re.match(r'^# [^#]', line) and not '{.tabset' in line:
        in_tabset = False
        first_section_after_tabset = True
        output.append(line)
        continue
    
    # If we're in a tabset section
    if in_tabset:
        # Convert h3 to h2 (subtopic tabs)
        if re.match(r'^### ', line):
            # These should be tab titles
            line = line.replace('###', '##', 1)
            output.append(line)
            continue
        
        # Convert h4 to h3 (chapters under tabs)
        elif re.match(r'^#### ', line):
            line = line.replace('####', '###', 1)
            output.append(line)
            continue
        
        # Convert h5 to h4
        elif re.match(r'^##### ', line):
            line = line.replace('#####', '####', 1)
            output.append(line)
            continue
    
    output.append(line)

with open('Atomic_Cosmic_RFView.Rmd', 'w', encoding='utf-8') as f:
    f.writelines(output)

print("Heading structure fixed for all tabset sections!")
