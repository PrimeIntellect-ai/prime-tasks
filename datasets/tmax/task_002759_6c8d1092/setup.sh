#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3
    pip3 install pytest pillow

    mkdir -p /app
    mkdir -p /home/user

    cat << 'EOF' > /app/setup.py
import sqlite3
import random
from datetime import datetime, timedelta
from PIL import Image, ImageDraw

# Generate Image
text = """Table researchers: id, name
Table experiments: id, researcher_id, name, status
Table measurements: id, exp_id, date, value
JOIN rules: researchers.id = experiments.researcher_id AND experiments.id = measurements.exp_id.
BUSINESS RULE: Always exclude experiments where status='REJECTED'. Only return measurements where value is greater than or equal to the provided minimum value."""

img = Image.new('RGB', (1000, 400), color='white')
d = ImageDraw.Draw(img)
d.text((10, 10), text, fill='black')
img.save('/app/schema_info.png')

# Generate DB
conn = sqlite3.connect('/home/user/research_data.db')
c = conn.cursor()

c.execute("CREATE TABLE researchers (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE experiments (id INTEGER PRIMARY KEY, researcher_id INTEGER, name TEXT, status TEXT)")
c.execute("CREATE TABLE measurements (id INTEGER PRIMARY KEY, exp_id INTEGER, date TEXT, value REAL)")

researchers = [f"Researcher_{i}" for i in range(1, 11)]
for i, name in enumerate(researchers, 1):
    c.execute("INSERT INTO researchers (id, name) VALUES (?, ?)", (i, name))

for i in range(1, 51):
    r_id = random.randint(1, 10)
    status = 'REJECTED' if i <= 10 else 'ACTIVE'
    c.execute("INSERT INTO experiments (id, researcher_id, name, status) VALUES (?, ?, ?, ?)", 
              (i, r_id, f"Exp_{i}", status))

start_date = datetime(2020, 1, 1)
for i in range(1, 501):
    e_id = random.randint(1, 50)
    date = (start_date + timedelta(days=random.randint(0, 1000))).strftime("%Y-%m-%d")
    val = round(random.uniform(0.0, 100.0), 2)
    c.execute("INSERT INTO measurements (id, exp_id, date, value) VALUES (?, ?, ?, ?)", 
              (i, e_id, date, val))

conn.commit()
conn.close()
EOF

    python3 /app/setup.py
    rm /app/setup.py

    cat << 'EOF' > /app/oracle_fetch.py
import sqlite3
import argparse
import json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--researcher', type=str, required=True)
    parser.add_argument('--min-val', type=float, required=True)
    args = parser.parse_args()

    conn = sqlite3.connect('/home/user/research_data.db')
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    query = """
        SELECT e.name as experiment_name, m.date as measurement_date, m.value as value
        FROM researchers r
        JOIN experiments e ON r.id = e.researcher_id
        JOIN measurements m ON e.id = m.exp_id
        WHERE r.name = ? 
          AND e.status != 'REJECTED'
          AND m.value >= ?
        ORDER BY m.date ASC, e.name ASC
    """

    cursor.execute(query, (args.researcher, args.min_val))
    rows = cursor.fetchall()

    result = []
    for row in rows:
        result.append({
            "experiment_name": row["experiment_name"],
            "measurement_date": row["measurement_date"],
            "value": row["value"]
        })

    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
