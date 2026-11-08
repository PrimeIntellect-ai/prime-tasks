#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    # 1. Create the SQLite database
    cat << 'EOF' > setup_db.py
import sqlite3
conn = sqlite3.connect('data.db')
c = conn.cursor()
c.execute("CREATE TABLE metrics (id INTEGER PRIMARY KEY, value REAL, status TEXT)")
c.execute("INSERT INTO metrics (value, status) VALUES (15.0, 'Active')")
c.execute("INSERT INTO metrics (value, status) VALUES (35.0, 'Active')")
c.execute("INSERT INTO metrics (value, status) VALUES (100.0, 'Inactive')")
conn.commit()
conn.close()
EOF
    python3 setup_db.py
    rm setup_db.py

    # 2. Create the broken .env file
    echo "CONVERGENCE_RATE=0.000001" > .env

    # 3. Create the Python script
    cat << 'EOF' > optimizer.py
import sqlite3
import os

def load_env():
    with open('/home/user/.env') as f:
        for line in f:
            if '=' in line:
                k, v = line.strip().split('=', 1)
                os.environ[k] = v

load_env()
rate = float(os.environ.get('CONVERGENCE_RATE', '0.001'))

conn = sqlite3.connect('/home/user/data.db')
c = conn.cursor()
# BUG: The status in DB is 'Active', but query uses 'active'
c.execute("SELECT value FROM metrics WHERE status = 'active'")
rows = c.fetchall()

if not rows:
    print("No data found!")
    exit(1)

val = sum(r[0] for r in rows)
target = 100.0
iterations = 0

while abs(val - target) > 0.1:
    val += (target - val) * rate
    iterations += 1
    if iterations > 1000:
        print("Convergence failure! Iteration limit exceeded.")
        exit(1)

print(f"Converged to {val:.2f}")
with open('/home/user/solution.txt', 'w') as f:
    f.write(f"{val:.2f}\n")
EOF
    chmod +x optimizer.py

    # 4. Create the memory dump
    head -c 1000 /dev/urandom > service_mem.dump
    echo -n "CRITICAL_ENV_VAR:CONVERGENCE_RATE=0.15" >> service_mem.dump
    head -c 500 /dev/urandom >> service_mem.dump

    chmod -R 777 /home/user
