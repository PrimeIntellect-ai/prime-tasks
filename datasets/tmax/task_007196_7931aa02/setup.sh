#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('etl_locks.db')
c = conn.cursor()
c.execute('''CREATE TABLE lock_waits (waiter_tx TEXT, holder_tx TEXT, wait_start_ms INTEGER)''')

# Insert non-cyclical data
c.execute("INSERT INTO lock_waits VALUES ('TX-88', 'TX-99', 1620000050)")
c.execute("INSERT INTO lock_waits VALUES ('TX-99', 'TX-105', 1620000080)")
c.execute("INSERT INTO lock_waits VALUES ('TX-11', 'TX-12', 1620000010)")

# Insert cyclical data (Deadlock: 42 -> 55 -> 61 -> 42)
c.execute("INSERT INTO lock_waits VALUES ('TX-42', 'TX-55', 1620000100)")
c.execute("INSERT INTO lock_waits VALUES ('TX-55', 'TX-61', 1620000150)")
c.execute("INSERT INTO lock_waits VALUES ('TX-61', 'TX-42', 1620000200)")

# Random other chain
c.execute("INSERT INTO lock_waits VALUES ('TX-70', 'TX-71', 1620000300)")

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
