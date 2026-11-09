#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 imagemagick tesseract-ocr fonts-dejavu-core
    pip3 install pytest pandas numpy

    mkdir -p /app

    # Create the database generation script
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random
import shutil

conn = sqlite3.connect('/app/clean_workload.db')
c = conn.cursor()
c.execute('CREATE TABLE data_points(id INTEGER PRIMARY KEY, x REAL, y REAL)')

data = []
for i in range(1, 10001):
    if i <= 50:
        val = random.uniform(-10.0, 10.0)
        data.append((i, val, val))
    else:
        data.append((i, random.uniform(-10.0, 10.0), random.uniform(-10.0, 10.0)))

random.shuffle(data)
data = [(i+1, d[1], d[2]) for i, d in enumerate(data)]

c.executemany('INSERT INTO data_points VALUES (?, ?, ?)', data)
conn.commit()
conn.close()

shutil.copy('/app/clean_workload.db', '/app/workload.db')
with open('/app/workload.db', 'r+b') as f:
    f.seek(16)
    f.write(b'corrupted_header1234')
EOF

    python3 /tmp/gen_db.py

    # Create the crash log
    cat << 'EOF' > /app/processor_crash.log
thread 'main' panicked at 'Attempted to divide by zero! x=y fallback not implemented. z-value calculation failed for x=4.2, y=4.2', src/main.rs:42
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace.
EOF

    # Create the formula image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 32 -fill black -draw "text 50,100 'f(x, y) = (x^3 + y^3) / (x - y)'" /app/formula.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
