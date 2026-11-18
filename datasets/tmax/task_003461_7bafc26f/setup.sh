#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 << 'EOF'
import os
import sqlite3
import base64
import json

os.makedirs('/home/user/ticket_system', exist_ok=True)
db_path = '/home/user/ticket_system/tickets.db'

# 1. Create SQLite DB
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE tickets (id INTEGER PRIMARY KEY, status TEXT, payload TEXT)')

# 2. Populate with 50 tickets
# Critical tickets will be at IDs 11, 22, and 45.
# ID 11 and 22 are specifically chosen to fall exactly on the skipped indices if the offset bug is present.
for i in range(1, 51):
    is_critical = (i in [11, 22, 45])
    data = {"critical": is_critical, "info": f"data_{i}"}

    json_str = json.dumps(data)
    b64_bytes = base64.b64encode(json_str.encode('utf-8'))
    b64_str = b64_bytes.decode('utf-8')

    payload_str = f"DATA:{b64_str}"

    c.execute("INSERT INTO tickets (id, status, payload) VALUES (?, ?, ?)", (i, 'closed', payload_str))

conn.commit()
conn.close()

# 3. Create the buggy report_generator.py
buggy_script = """#!/usr/bin/env python3
import sqlite3
import base64
import json
import sys

def process_payload(payload_str):
    # Strip the "DATA:" prefix
    # BUG 1: The developer mistakenly used -1, chopping off the last character of the base64 string
    b64_part = payload_str[5:-1]

    try:
        # validate=True ensures it strictly checks padding and alphabet
        decoded = base64.b64decode(b64_part, validate=True)
        return json.loads(decoded.decode('utf-8'))
    except Exception as e:
        raise ValueError(f"Decoding failed for payload: {e}")

def generate_report():
    conn = sqlite3.connect('/home/user/ticket_system/tickets.db')
    cursor = conn.cursor()

    batch_size = 10
    offset = 0
    results = []

    while True:
        cursor.execute("SELECT id, payload FROM tickets ORDER BY id LIMIT ? OFFSET ?", (batch_size, offset))
        rows = cursor.fetchall()

        if not rows:
            break

        for row in rows:
            t_id, payload = row
            try:
                data = process_payload(payload)
                if data.get('critical'):
                    results.append(t_id)
            except Exception as e:
                with open('/home/user/ticket_system/error.log', 'w') as f:
                    f.write(f"Crash on Ticket {t_id}: {str(e)}\\n")
                print(f"Error processing ticket {t_id}. See error.log.")
                sys.exit(1)

        # BUG 2: Off-by-one in pagination. Skips the 11th, 22nd, 33rd etc. records.
        offset += batch_size + 1

    with open('/home/user/ticket_system/critical_tickets.json', 'w') as f:
        json.dump(results, f)
    print("Report generated successfully.")

if __name__ == '__main__':
    generate_report()
"""

with open('/home/user/ticket_system/report_generator.py', 'w') as f:
    f.write(buggy_script)

os.chmod('/home/user/ticket_system/report_generator.py', 0o755)
EOF

    chmod -R 777 /home/user
