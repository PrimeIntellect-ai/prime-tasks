#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/graph.db')
c = conn.cursor()
c.execute("CREATE TABLE edges (src TEXT, dst TEXT, relation TEXT, timestamp INTEGER, is_deleted INTEGER)")

# Data:
# Triangle 1: A, B, C
# A->B
c.execute("INSERT INTO edges VALUES ('A', 'B', 'KNOWS', 100, 0)")
# B->C
c.execute("INSERT INTO edges VALUES ('B', 'C', 'KNOWS', 101, 0)")
# C->A
c.execute("INSERT INTO edges VALUES ('C', 'A', 'KNOWS', 102, 0)")

# Stale data for Triangle 1
c.execute("INSERT INTO edges VALUES ('A', 'B', 'KNOWS', 50, 1)") # Was deleted, then re-added

# Fake Triangle (C->D->E->C) but E->C is deleted
c.execute("INSERT INTO edges VALUES ('C', 'D', 'KNOWS', 103, 0)")
c.execute("INSERT INTO edges VALUES ('D', 'E', 'KNOWS', 104, 0)")
c.execute("INSERT INTO edges VALUES ('E', 'C', 'KNOWS', 105, 0)")
c.execute("INSERT INTO edges VALUES ('E', 'C', 'KNOWS', 106, 1)") # Deleted later!

# Triangle 2: X, Y, Z
c.execute("INSERT INTO edges VALUES ('X', 'Y', 'KNOWS', 200, 0)")
c.execute("INSERT INTO edges VALUES ('Y', 'Z', 'KNOWS', 200, 0)")
c.execute("INSERT INTO edges VALUES ('Z', 'X', 'KNOWS', 200, 0)")
# Noise
c.execute("INSERT INTO edges VALUES ('X', 'Z', 'LIKES', 200, 0)")

c.execute("CREATE INDEX bad_idx ON edges(src)")

conn.commit()
conn.close()
EOF
    python3 /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
