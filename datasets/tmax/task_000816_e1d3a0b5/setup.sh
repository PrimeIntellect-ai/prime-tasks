#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow pytesseract

    mkdir -p /app/.hidden

    cat << 'EOF' > /tmp/setup.py
import os
from PIL import Image, ImageDraw
import csv
import random
import datetime

# Generate image
img = Image.new('RGB', (800, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = r"EventID:\s*([A-Z0-9]{8})\s*\|\s*Gate:\s*(PASSED|FAILED|PENDING)"
d.text((10, 40), text, fill=(0, 0, 0))
img.save('/app/target_pattern.png')

# Generate logs
random.seed(42)
logs = []
reference = []

start_time = datetime.datetime(2023, 1, 1)

for i in range(10000):
    session = f"SESS_{random.randint(1000, 9999)}"
    ts = (start_time + datetime.timedelta(minutes=i)).isoformat()

    r = random.random()
    if r < 0.05:
        # target regex, no newline
        eid = f"{random.randint(10000000, 99999999):08d}"
        gate = random.choice(["PASSED", "FAILED", "PENDING"])
        msg = f"Some prefix EventID: {eid} | Gate: {gate} suffix"
        logs.append([session, ts, msg])
        reference.append([session, ts, eid, gate])
    elif r < 0.15:
        # newline, no target
        msg = f"Line1\nLine2\nLine3 error {i}"
        logs.append([session, ts, msg])
    elif r < 0.17:
        # target regex AND newline
        eid = f"{random.randint(10000000, 99999999):08d}"
        gate = random.choice(["PASSED", "FAILED", "PENDING"])
        msg = f"Line1\nEventID: {eid} | Gate: {gate}\nLine3"
        logs.append([session, ts, msg])
        reference.append([session, ts, eid, gate])
    else:
        # normal
        msg = f"Normal log message {i}"
        logs.append([session, ts, msg])

with open('/app/system_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['SessionID', 'Timestamp', 'LogMessage'])
    writer.writerows(logs)

reference.sort(key=lambda x: (x[0], x[1]))
with open('/app/.hidden/reference_logs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['SessionID', 'Timestamp', 'EventID', 'GateStatus'])
    writer.writerows(reference)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
