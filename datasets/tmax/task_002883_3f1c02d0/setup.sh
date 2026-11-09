#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/financial_logs.db')
c = conn.cursor()
c.execute('''CREATE TABLE transfers (id INTEGER PRIMARY KEY, sender TEXT, receiver TEXT, amount REAL, date TEXT)''')

data = [
    # Path 1: C-100 -> M -> C-999 (Sum: 1000)
    ('C-100', 'M', 500.0), ('M', 'C-999', 500.0),
    # Path 2: C-100 -> X -> Y -> Z -> C-999 (Sum: 800)
    ('C-100', 'X', 200.0), ('X', 'Y', 200.0), ('Y', 'Z', 200.0), ('Z', 'C-999', 200.0),
    # Path 3: C-100 -> P -> Q -> C-999 (Sum: 450)
    ('C-100', 'P', 150.0), ('P', 'Q', 150.0), ('Q', 'C-999', 150.0),
    # Path 4: C-100 -> A -> B -> C-999 (Sum: 300)
    ('C-100', 'A', 100.0), ('A', 'B', 100.0), ('B', 'C-999', 100.0),
    # Path 5: C-100 -> S -> C-999 (Sum: 140)
    ('C-100', 'S', 70.0), ('S', 'C-999', 70.0),
    # Path 6: C-100 -> R -> C-999 (Sum: 120)
    ('C-100', 'R', 60.0), ('R', 'C-999', 60.0),
    # Path 7: C-100 -> N -> C-999 (Sum: 540)
    ('C-100', 'N', 40.0), ('N', 'C-999', 500.0),
    # Noise data
    ('C-100', 'NOISE1', 500.0)
]

for idx, (s, r, a) in enumerate(data):
    c.execute("INSERT INTO transfers (sender, receiver, amount, date) VALUES (?, ?, ?, '2023-10-01')", (s, r, a))

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
