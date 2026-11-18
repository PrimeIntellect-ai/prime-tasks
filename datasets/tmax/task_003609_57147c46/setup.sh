#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'US_EAST: 0.12\nUS_WEST: 0.17\nEU_CENTRAL: 0.22', fill=(0,0,0))
img.save('/app/rates.png')
"

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/billing_alert_oracle.py
#!/usr/bin/env python3
import sys

rates = {
    "US_EAST": 0.12,
    "US_WEST": 0.17,
    "EU_CENTRAL": 0.22
}

total = 0.0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split()
    if len(parts) == 2:
        region = parts[0]
        hours = int(parts[1])
        if region in rates:
            total += rates[region] * hours

print("From: finops@local")
print("To: billing-alerts@local")
print("Subject: Daily Cloud Cost Alert")
print()
print(f"Total Cost: ${total:.2f}")
EOF
    chmod +x /opt/oracle/billing_alert_oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
