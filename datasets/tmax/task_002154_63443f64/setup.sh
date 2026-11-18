#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3 golang-go
    pip3 install pytest Pillow

    mkdir -p /app/telemetry /app/corpus/evil /app/corpus/clean

    python3 -c "
import os
import sqlite3
from PIL import Image, ImageDraw

# Image
img = Image.new('RGB', (400, 200), color = (0, 0, 0))
d = ImageDraw.Draw(img)
d.text((10,10), 'CRITICAL ALERT: Node memory exhausted.\nIncident Trace-ID: 8F92A1B7\nTime: 2023-10-24', fill=(255,255,255))
img.save('/app/alert.png')

# SQLite
conn = sqlite3.connect('/app/telemetry/logs.db')
c = conn.cursor()
c.execute('CREATE TABLE dumps (trace_id TEXT, dump_text TEXT)')
c.execute(\"INSERT INTO dumps VALUES ('8F92A1B7', 'goroutine 123 [chan send]:\\ngithub.com/company/srv/worker.flushBuffer(...)')\")
conn.commit()
conn.close()

with open('/app/telemetry/logs.db', 'r+b') as f:
    f.write(b'CorruptedHeader123')

# Corpora
for i in range(20):
    with open(f'/app/corpus/evil/dump_{i}.txt', 'w') as f:
        f.write(f'goroutine {i} [chan send]:\\ngithub.com/company/srv/worker.flushBuffer(...)\\n')

for i in range(20):
    with open(f'/app/corpus/clean/dump_{i}.txt', 'w') as f:
        f.write(f'goroutine {i} [running]:\\nnet/http.(*connReader).backgroundRead(...)\\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
