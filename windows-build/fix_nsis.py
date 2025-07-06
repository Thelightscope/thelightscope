#!/usr/bin/env python3
"""
Fix special characters in NSIS installer script that cause compilation errors
"""

import re

# Read the NSIS file
with open('lightscope-installer.nsi', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace problematic characters in DetailPrint statements
# Remove check marks and X marks that cause NSIS syntax errors
content = re.sub(r'DetailPrint "âœ" ([^"]+)"', r'DetailPrint "\1"', content)
content = re.sub(r'DetailPrint "âœ— ([^"]+)"', r'DetailPrint "WARNING: \1"', content)

# Write the fixed content back
with open('lightscope-installer.nsi', 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed special characters in NSIS installer script") 