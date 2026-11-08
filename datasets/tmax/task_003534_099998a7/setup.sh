#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr libtesseract-dev
    pip3 install pytest pytesseract Pillow

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import random
import os
from PIL import Image, ImageDraw

# 1. Create Image
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "AUDIT POLICY v2.4\nFlag any employee whose out-of-department access severity sums to > 100 within any 14-day window."
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/policy.png')

# 2. Create DB
db_path = '/home/user/audit.db'
if os.path.exists(db_path):
    os.remove(db_path)
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, emp_uid TEXT, dept_id INTEGER)')
c.execute('CREATE TABLE access_logs (id INTEGER PRIMARY KEY, emp_uid TEXT, resource_dept_id INTEGER, access_time INTEGER, severity INTEGER)')

random.seed(42)
employees = []
for i in range(1, 2001):
    emp_uid = f"E-{i:04d}"
    dept_id = random.randint(1, 10)
    employees.append((emp_uid, dept_id))
    c.execute('INSERT INTO employees (emp_uid, dept_id) VALUES (?, ?)', (emp_uid, dept_id))

logs = []
for i in range(50000):
    emp = random.choice(employees)
    emp_uid = emp[0]
    resource_dept_id = random.randint(1, 10)
    access_time = random.randint(0, 60 * 86400)
    severity = random.randint(1, 15)
    logs.append((emp_uid, resource_dept_id, access_time, severity))

# Ensure breaches
for i in range(30):
    emp = employees[i]
    emp_uid = emp[0]
    base_time = random.randint(0, 40 * 86400)
    for j in range(10):
        res_dept = emp[1] + 1 if emp[1] < 10 else 1
        logs.append((emp_uid, res_dept, base_time + j * 86400, 15))

c.executemany('INSERT INTO access_logs (emp_uid, resource_dept_id, access_time, severity) VALUES (?, ?, ?, ?)', logs)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py

    cat << 'EOF' > /home/user/generate_report.py
import sqlite3
import json

def main():
    conn = sqlite3.connect('/home/user/audit.db')
    cur = conn.cursor()

    # Inefficient query with implicit cross join
    query = """
    SELECT e.emp_uid, a.severity
    FROM employees e, access_logs a
    """
    cur.execute(query)
    results = cur.fetchmany(10) # Just fetch a few so it doesn't hang forever in initial state

    with open('/home/user/compliance_report.json', 'w') as f:
        json.dump([], f)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
