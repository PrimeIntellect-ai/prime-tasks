#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import random
from datetime import datetime, timedelta

random.seed(42)

conn = sqlite3.connect('/home/user/audit.db')
c = conn.cursor()

c.execute('''CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER,
    permissions TEXT
)''')

c.execute('''CREATE TABLE access_logs (
    id INTEGER PRIMARY KEY,
    employee_id INTEGER,
    resource_owner_id INTEGER,
    timestamp DATETIME,
    action TEXT
)''')

# Generate Hierarchy
# 1 CEO
# 10 VPs
# 50 Directors
# 200 Managers
# 1000 ICs
employees = []
permissions_pool = ["READ", "WRITE", "DELETE", "EXECUTE"]

# CEO
employees.append((1, "CEO", None, json.dumps(["READ", "APPROVE_FUNDS"])))

# VPs (manager: 1)
for i in range(2, 12):
    employees.append((i, f"VP_{i}", 1, json.dumps(["READ", "APPROVE_FUNDS"])))

# Directors (managers: 2-11)
for i in range(12, 62):
    employees.append((i, f"Dir_{i}", random.randint(2, 11), json.dumps(["READ"])))

# Managers (managers: 12-61)
for i in range(62, 262):
    p = ["READ", "REQUEST_FUNDS"]
    if random.random() < 0.05: # Toxic combo
        p.append("APPROVE_FUNDS")
    employees.append((i, f"Mgr_{i}", random.randint(12, 61), json.dumps(p)))

# ICs (managers: 62-261)
for i in range(262, 1262):
    p = ["READ", random.choice(permissions_pool)]
    if random.random() < 0.02: # Toxic combo
        p.extend(["APPROVE_FUNDS", "REQUEST_FUNDS"])
    employees.append((i, f"IC_{i}", random.randint(62, 261), json.dumps(list(set(p)))))

c.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)", employees)

# Generate Access Logs
logs = []
start_date = datetime(2023, 1, 1)

# Generate valid accesses (manager accessing report, or self)
# Generate invalid accesses
# Generate anomalous volumes
for i in range(1, 5001):
    emp_id = random.randint(1, 1261)
    # 80% self, 10% valid manager, 10% invalid
    rand_val = random.random()
    if rand_val < 0.8:
        owner_id = emp_id
    elif rand_val < 0.9:
        # Just pick a random owner, might be invalid
        owner_id = random.randint(1, 1261)
    else:
        owner_id = 1 # accessing CEO, always invalid unless emp_id=1

    ts = start_date + timedelta(days=random.randint(0, 30), hours=random.randint(0, 23))
    logs.append((i, emp_id, owner_id, ts.strftime('%Y-%m-%d %H:%M:%S'), "READ"))

# Force an anomalous volume for employee 500 and 600
for i in range(10):
    ts = start_date + timedelta(days=1, hours=i)
    logs.append((5001 + i, 500, 500, ts.strftime('%Y-%m-%d %H:%M:%S'), "READ"))
for i in range(10):
    ts = start_date + timedelta(days=15, hours=i)
    logs.append((5011 + i, 600, 600, ts.strftime('%Y-%m-%d %H:%M:%S'), "READ"))

c.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?, ?)", logs)
conn.commit()
conn.close()
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
