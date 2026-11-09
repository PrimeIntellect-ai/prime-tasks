#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip tesseract-ocr
    pip3 install pytest pillow flask fastapi uvicorn requests pytesseract

    mkdir -p /app
    cat << 'EOF' > /app/setup.py
import sqlite3
import random
from PIL import Image, ImageDraw

# Generate image
img = Image.new('RGB', (300, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), "IGNORE_DEPT_ID: 854", fill=(0, 0, 0))
img.save('/app/exclude_rule.png')

conn = sqlite3.connect('/app/company.db')
c = conn.cursor()
c.execute('CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER)')
c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER)')

# Insert departments
deps = [(1, 'HQ', None)]
for i in range(2, 1001):
    deps.append((i, f'Dept_{i}', random.randint(1, i-1)))
c.executemany('INSERT INTO departments VALUES (?, ?, ?)', deps)

# Ensure 854 is a child of 1 directly or indirectly to test exclusion
c.execute('UPDATE departments SET parent_id = 1 WHERE id = 854')

# Insert employees
emps = []
for i in range(1, 50001):
    emps.append((i, f'Employee_{i:05d}', random.randint(1, 1000)))
c.executemany('INSERT INTO employees VALUES (?, ?, ?)', emps)

conn.commit()
conn.close()
EOF

    python3 /app/setup.py
    rm /app/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
