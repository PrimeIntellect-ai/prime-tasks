#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/project

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

os.makedirs('/home/user/project', exist_ok=True)
conn = sqlite3.connect('/home/user/project/data.db')
c = conn.cursor()
c.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, year INTEGER, month INTEGER, day INTEGER, amount REAL)')

# Insert 2022 data (wrong year fallback)
for i in range(10):
    c.execute('INSERT INTO transactions (year, month, day, amount) VALUES (?, ?, ?, ?)', (2022, 10, i+1, 999.99))

# Insert 2023 data
amounts = [1.1, 2.2, 3.3, 4.4, 5.5, 0.1, 0.2] * 10
for i, amt in enumerate(amounts):
    day = (i % 31) + 1
    c.execute('INSERT INTO transactions (year, month, day, amount) VALUES (?, ?, ?, ?)', (2023, 10, day, amt))

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py

    cat << 'EOF' > /home/user/project/build.sh
#!/bin/bash
export REPORT_MONTH=10
# BUG 1: Missing REPORT_YEAR. Should be: export REPORT_YEAR=2023
export REPORT_YEAR=2022

python3 process_data.py
python3 validate.py
EOF
    chmod +x /home/user/project/build.sh

    cat << 'EOF' > /home/user/project/process_data.py
import sqlite3
import os
import json

year = int(os.environ.get('REPORT_YEAR', 2022))
month = int(os.environ.get('REPORT_MONTH', 10))

conn = sqlite3.connect('data.db')
c = conn.cursor()

# BUG 2: Boundary condition. day > 1 AND day < 31 misses boundaries. Should be >= 1 and <= 31
query = f"SELECT amount FROM transactions WHERE year = {year} AND month = {month} AND day > 1 AND day < 31"
c.execute(query)
rows = c.fetchall()

total = 0.0
for row in rows:
    # BUG 3: Precision loss. total += row[0] with floats.
    total += row[0]

with open('output.json', 'w') as f:
    json.dump({"year": year, "month": month, "total": total}, f)
EOF

    cat << 'EOF' > /home/user/project/validate.py
import json
import sys

try:
    with open('output.json', 'r') as f:
        data = json.load(f)
except FileNotFoundError:
    print("output.json not found!")
    sys.exit(1)

if data.get("year") != 2023:
    print(f"Validation failed: Expected year 2023, got {data.get('year')}")
    sys.exit(1)

expected_total = 168.0
# We want an exact match to ensure they fixed the precision issue, not just rounded.
if data.get("total") != expected_total:
    print(f"Validation failed: Expected total {expected_total}, got {data.get('total')}. Precision loss detected or incorrect row count.")
    sys.exit(1)

print("Build passed!")
sys.exit(0)
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
