#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install --default-timeout=100 pytest Pillow

    mkdir -p /app /opt

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
text = """DATA CLEANING RULES:
1. ID: Must be zero-padded to 8 digits. If missing, use 00000000.
2. Temperature: If missing, "NaN", or invalid, substitute with 0.0. Round all valid numbers to 1 decimal place.
3. Status: Map 'A' -> 'Active', 'I' -> 'Inactive'. Any other value or missing -> 'Unknown'.
4. Date: Pass through exactly as provided."""
img = Image.new('RGB', (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/schema_rules.png')
EOF
    python3 /tmp/make_image.py

    cat << 'EOF' > /opt/oracle_cleaner.py
import sys
import math

def clean(row):
    parts = row.split(',')
    if len(parts) != 4: return "00000000,0.0,Unknown,"

    # Rule 1
    try:
        id_val = str(int(parts[0])).zfill(8)
    except:
        id_val = "00000000"

    # Rule 2
    try:
        temp_val = float(parts[1])
        if math.isnan(temp_val):
            temp_str = "0.0"
        else:
            temp_str = f"{temp_val:.1f}"
    except:
        temp_str = "0.0"

    # Rule 3
    stat = parts[2].strip()
    if stat == 'A':
        stat_str = 'Active'
    elif stat == 'I':
        stat_str = 'Inactive'
    else:
        stat_str = 'Unknown'

    # Rule 4
    date_str = parts[3]

    return f"{id_val},{temp_str},{stat_str},{date_str}"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(clean(sys.argv[1]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
