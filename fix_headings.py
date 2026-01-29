#!/usr/bin/env python3
"""
Fix heading structure for proper TOC display:
- Remove h2 lines that only contain {.tabset .tabset-pills}
- Convert h3 (###) to h2 (##) - these become sub-topics
- Convert h4 (####) to h3 (###) - these become chapters
- Convert h5 (#####) to h4 (####) - these become sub-chapters
"""

import re

with open('Atomic_Cosmic_RFView.Rmd', 'r', encoding='utf-8') as f:
    lines = f.readlines()

output = []
i = 0
while i < len(lines):
    line = lines[i]
    
    # Skip h2 lines with only tabset class
    if line.strip() == '## {.tabset .tabset-pills}':
        i += 1
        continue
    
    # Convert h5 to h4
    if re.match(r'^##### ', line):
        line = line.replace('#####', '####', 1)
        output.append(line)
        i += 1
        continue
    
    # Convert h4 to h3
    if re.match(r'^#### ', line):
        line = line.replace('####', '###', 1)
        output.append(line)
        i += 1
        continue
    
    # Convert h3 to h2
    if re.match(r'^### ', line):
        line = line.replace('###', '##', 1)
        output.append(line)
        i += 1
        continue
    
    output.append(line)
    i += 1

with open('Atomic_Cosmic_RFView.Rmd', 'w', encoding='utf-8') as f:
    f.writelines(output)

print("Heading levels converted successfully!")
print("Structure: h1 (Main topics) -> h2 (Sub-topics) -> h3 (Chapters) -> h4 (Sub-chapters)")

