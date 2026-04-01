#!/usr/bin/env python3
import os

# File path
file_path = r'D:\GitHub\Atomic_cosmic_RFView_Notes\PA design App\R\app.R'

# Step 1: Check if file exists
if not os.path.exists(file_path):
    print(f'ERROR: File not found at {file_path}')
    exit(1)

# Step 2: Read the file in binary mode
with open(file_path, 'rb') as f:
    content = f.read()

print(f'File size: {len(content)} bytes')
print(f'First 10 bytes (hex): {content[:10].hex()}')

# Check for UTF-8 BOM
utf8_bom = b'\xef\xbb\xbf'
has_bom = content.startswith(utf8_bom)

if has_bom:
    print('✓ UTF-8 BOM detected (EF BB BF)')
    print('Removing BOM...')
    
    # Remove the BOM
    content_without_bom = content[3:]
    
    # Write back to file
    with open(file_path, 'wb') as f:
        f.write(content_without_bom)
    
    print('✓ BOM removed and file saved')
    
    # Verify the fix
    with open(file_path, 'rb') as f:
        new_content = f.read()
    
    print(f'New file size: {len(new_content)} bytes')
    print(f'First 10 bytes (hex): {new_content[:10].hex()}')
    
    if new_content.startswith(utf8_bom):
        print('ERROR: BOM still present after removal!')
    else:
        print('✓ VERIFIED: BOM successfully removed!')
else:
    print('ℹ No UTF-8 BOM detected - file appears to be clean')
    print(f'First 10 bytes (hex): {content[:10].hex()}')
