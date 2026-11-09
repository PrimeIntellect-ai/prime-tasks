#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak
    pip3 install pytest

    mkdir -p /app

    # Generate voicemail
    espeak -w /app/voicemail.wav "We need to audit the exposure. Write a script to compute the total sum of all outbound transfer amounts up to depth two. That means direct outbound transfers, plus the outbound transfers of those direct recipients. The index named idx_corrupted_src is returning stale data, so be sure your script drops it before running the queries."

    # Generate database
    cat << 'EOF' > /app/setup_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/app/ledger.db')
cursor = conn.cursor()
cursor.execute('CREATE TABLE transfers (src INTEGER, dst INTEGER, amount INTEGER)')

data = []
for _ in range(5000):
    src = random.randint(1, 1000)
    dst = random.randint(1, 1000)
    amount = random.randint(10, 10000)
    data.append((src, dst, amount))

cursor.executemany('INSERT INTO transfers VALUES (?, ?, ?)', data)
cursor.execute('CREATE INDEX idx_corrupted_src ON transfers(src)')
conn.commit()
conn.close()
EOF
    python3 /app/setup_db.py

    # Create oracle
    cat << 'EOF' > /app/oracle_audit.py
import sys
import sqlite3

def solve(account_id):
    conn = sqlite3.connect('/app/ledger.db')
    cursor = conn.cursor()
    cursor.execute("DROP INDEX IF EXISTS idx_corrupted_src")

    # Depth 1 and 2 outbound sum
    query = """
    WITH RECURSIVE
      depth1 AS (
        SELECT dst, amount FROM transfers WHERE src = ?
      ),
      depth2 AS (
        SELECT t.amount FROM depth1 d JOIN transfers t ON d.dst = t.src
      )
    SELECT COALESCE((SELECT SUM(amount) FROM depth1), 0) + 
           COALESCE((SELECT SUM(amount) FROM depth2), 0)
    """
    cursor.execute(query, (account_id,))
    result = cursor.fetchone()[0]
    print(result)

if __name__ == "__main__":
    solve(int(sys.argv[1]))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
