#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/setup_data.py
import sqlite3
import json

# 1. Create employees.db
conn = sqlite3.connect('/home/user/employees.db')
c = conn.cursor()
c.execute("CREATE TABLE employees (emp_id TEXT PRIMARY KEY, department TEXT)")

# E9 is a ghost employee (not in DB)
employees = [
    ("E1", "IT"),
    ("E2", "HR"),
    ("E3", "IT"),
    ("E4", "ENG"),
    ("E5", "ENG"),
    ("E6", "FIN"),
    ("E7", "FIN"),
    ("E8", "EXEC")
]
c.executemany("INSERT INTO employees VALUES (?, ?)", employees)
conn.commit()
conn.close()

# 2. Create delegations.jsonl
delegations = [
    # Cycle 1: E1 -> E2 -> E3 -> E1
    {"from_emp": "E1", "to_emp": "E2"},
    {"from_emp": "E2", "to_emp": "E3"},
    {"from_emp": "E3", "to_emp": "E1"},

    # Cycle 2: E4 -> E5 -> E6 -> E4
    {"from_emp": "E4", "to_emp": "E5"},
    {"from_emp": "E5", "to_emp": "E6"},
    {"from_emp": "E6", "to_emp": "E4"},

    # Connections bridging cycles
    {"from_emp": "E3", "to_emp": "E4"},
    {"from_emp": "E1", "to_emp": "E6"},

    # Cycle 3: E6 -> E7 -> E8 -> E6
    {"from_emp": "E6", "to_emp": "E7"},
    {"from_emp": "E7", "to_emp": "E8"},
    {"from_emp": "E8", "to_emp": "E6"},

    # Ghost delegations (should be ignored)
    {"from_emp": "E8", "to_emp": "E9"},
    {"from_emp": "E9", "to_emp": "E1"},
    {"from_emp": "E2", "to_emp": "E9"}
]

with open('/home/user/delegations.jsonl', 'w') as f:
    for d in delegations:
        f.write(json.dumps(d) + "\n")
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
