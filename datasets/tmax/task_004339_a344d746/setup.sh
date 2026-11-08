#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytz Pillow pytesseract

    # Create the dashboard snapshot image using Pillow
    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10, 40), 'Peak Multiplier: 1.45', fill='black')
img.save('/app/dashboard_snapshot.png')
"

    # Create the oracle script
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/projector_oracle
#!/usr/bin/env python3
import sys
from datetime import datetime
import pytz

multiplier = 1.45
berlin_tz = pytz.timezone('Europe/Berlin')

for line in sys.stdin:
    line = line.strip()
    if not line: continue
    ts_str, service, cpu_str, mem_str = line.split(',')

    # Parse UTC time
    dt_utc = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
    dt_utc = pytz.utc.localize(dt_utc)

    # Convert to Berlin
    dt_berlin = dt_utc.astimezone(berlin_tz)
    ts_berlin_str = dt_berlin.strftime("%Y/%m/%d %H:%M:%S")

    cpu = float(cpu_str) * multiplier
    mem = float(mem_str) * multiplier

    print(f"[{ts_berlin_str}] {service}: CPU={cpu:.2f}, MEM={mem:.2f}")
EOF
    chmod +x /opt/oracle/projector_oracle

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
