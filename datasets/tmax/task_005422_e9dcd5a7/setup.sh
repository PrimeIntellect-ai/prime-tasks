#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the config image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 50), 'AUTH_TOKEN: SCARLET-MACAW-77', fill=(0, 0, 0))
d.text((10, 100), 'THRESHOLD: MEAN + 3 * STDDEV', fill=(0, 0, 0))
img.save('/app/config.png')
"

    # Generate the database and leave a WAL file
    sqlite3 /app/logs.db "PRAGMA journal_mode=WAL; CREATE TABLE access_logs (ip_address TEXT, request_count INTEGER);"
    sqlite3 /app/logs.db "INSERT INTO access_logs VALUES ('192.168.1.1', 20), ('192.168.1.2', 35), ('192.168.1.3', 15), ('192.168.1.4', 40), ('192.168.1.5', 25), ('10.0.0.99', 4500), ('192.168.1.105', 5000);"

    # Ensure WAL file exists for the test
    touch /app/logs.db-wal

    # Create the buggy analyzer script
    cat << 'EOF' > /app/analyzer.py
import sqlite3
import math

def get_anomalies(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT ip_address, request_count FROM access_logs")
    data = c.fetchall()

    if not data:
        return []

    counts = [row[1] for row in data]
    mean = sum(counts) / len(counts)

    # Bug: population stddev instead of sample stddev (dividing by N instead of N-1)
    variance = sum((x - mean) ** 2 for x in counts) / len(counts)
    stddev = math.sqrt(variance)

    # Bug: hardcoded threshold instead of using the formula
    threshold = 100 

    anomalies = []
    for ip, count in data:
        if count > threshold:
            anomalies.append(ip)

    return sorted(anomalies)
EOF

    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
