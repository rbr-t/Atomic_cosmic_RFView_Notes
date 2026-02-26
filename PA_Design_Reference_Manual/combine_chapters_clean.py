#!/usr/bin/env python3
"""
Properly combine chapter HTML files by extracting content and removing tabset structures
"""

import re
from pathlib import Path

def extract_head_section(html_content):
    """Extract the complete head section from HTML"""
    head_match = re.search(r'(<head>.*?</head>)', html_content, re.DOTALL)
    if head_match:
        return head_match.group(1)
    return ""

def extract_body_content(html_content, remove_tabsets=False):
    """
    Extract body content from HTML
    If remove_tabsets is True, convert tabset sections to regular sections
    """
    # Find the main content div
    body_match = re.search(r'<body[^>]*>(.*)</body>', html_content, re.DOTALL)
    if not body_match:
        return ""
    
    body_content = body_match.group(1)
    
    if remove_tabsets:
        # Remove tabset classes from section divs
        body_content = re.sub(r'class="([^"]*)\btabset\b([^"]*)"', r'class="\1\2"', body_content)
        body_content = re.sub(r'class="([^"]*)\btabset-fade\b([^"]*)"', r'class="\1\2"', body_content)
        body_content = re.sub(r'class="([^"]*)\btabset-pills\b([^"]*)"', r'class="\1\2"', body_content)
        
        # Clean up any double spaces in class attributes
        body_content = re.sub(r'class="\s+', 'class="', body_content)
        body_content = re.sub(r'\s+"', '"', body_content)
        body_content = re.sub(r'class="\s*"', '', body_content)
    
    return body_content

def main():
    base_dir = Path(__file__).parent
    
    # Read the three chapter files
    print("Reading chapter files...")
    
    ch01_path = base_dir / "Chapters" / "Chapter_01_Transistor_Fundamentals.html"
    ch05_path = base_dir / "manual_chapters" / "ch05_thermal" / "Chapter_05_Advanced_Techniques.html"
    ch06_path = base_dir / "manual_chapters" / "ch06_integration" / "Chapter_06_Lessons_Learned.html"
    
    with open(ch01_path, 'r', encoding='utf-8') as f:
        ch01_html = f.read()
    
    with open(ch05_path, 'r', encoding='utf-8') as f:
        ch05_html = f.read()
    
    with open(ch06_path, 'r', encoding='utf-8') as f:
        ch06_html = f.read()
    
    print("Extracting sections...")
    
    # Extract head from Chapter 01
    head_section = extract_head_section(ch01_html)
    
    # Extract body content from all chapters
    # For Chapter 01, remove tabset structures
    ch01_body = extract_body_content(ch01_html, remove_tabsets=True)
    ch05_body = extract_body_content(ch05_html, remove_tabsets=False)
    ch06_body = extract_body_content(ch06_html, remove_tabsets=False)
    
    # Build the combined HTML
    combined_html = f"""<!DOCTYPE html>
<html>

{head_section}

<body>
{ch01_body}

{ch05_body}

{ch06_body}
</body>

</html>
"""
    
    # Write output
    output_path = Path(__file__).parent / "PA_Design_Manual_Complete_v2.html"
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(combined_html)
    
    # Calculate stats
    combined_lines = combined_html.count('\n')
    ch01_lines = ch01_body.count('\n')
    ch05_lines = ch05_body.count('\n')
    ch06_lines = ch06_body.count('\n')
    
    print(f"\n✅ Chapters combined successfully!")
    print(f"Output file: {output_path.name}")
    print(f"Total lines: {combined_lines:,}")
    print(f"\nStructure:")
    print(f"- Head section from Chapter 01")
    print(f"- Chapter 01 content ({ch01_lines:,} lines) - tabsets removed")
    print(f"- Chapter 05 content ({ch05_lines:,} lines)")
    print(f"- Chapter 06 content ({ch06_lines:,} lines)")

if __name__ == "__main__":
    main()
