#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import random

db_path = '/home/user/financial_graph.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp TEXT)''')

# Generate normal entities and transactions
for i in range(1, 101):
    c.execute("INSERT INTO entities (id, name) VALUES (?, ?)", (i, f"Entity_{i}"))

tx_id = 1
for _ in range(500):
    s = random.randint(1, 100)
    r = random.randint(1, 100)
    if s != r:
        c.execute("INSERT INTO transactions VALUES (?, ?, ?, ?, '2023-01-01')", (tx_id, s, r, random.uniform(100, 5000)))
        tx_id += 1

# Inject specific circular patterns > 10000
# Chain 1: 10 -> 20 -> 30 -> 10
c.execute("INSERT INTO transactions VALUES (?, 10, 20, 15000, '2023-01-02')", (tx_id,)); tx_id+=1
c.execute("INSERT INTO transactions VALUES (?, 20, 30, 12000, '2023-01-03')", (tx_id,)); tx_id+=1
c.execute("INSERT INTO transactions VALUES (?, 30, 10, 11000, '2023-01-04')", (tx_id,)); tx_id+=1

# Chain 2: 45 -> 55 -> 65 -> 45
c.execute("INSERT INTO transactions VALUES (?, 45, 55, 25000, '2023-01-02')", (tx_id,)); tx_id+=1
c.execute("INSERT INTO transactions VALUES (?, 55, 65, 22000, '2023-01-03')", (tx_id,)); tx_id+=1
c.execute("INSERT INTO transactions VALUES (?, 65, 45, 21000, '2023-01-04')", (tx_id,)); tx_id+=1

# False Chain (Amount too low): 70 -> 80 -> 90 -> 70
c.execute("INSERT INTO transactions VALUES (?, 70, 80, 15000, '2023-01-02')", (tx_id,)); tx_id+=1
c.execute("INSERT INTO transactions VALUES (?, 80, 90, 5000, '2023-01-03')", (tx_id,)); tx_id+=1  # < 10000
c.execute("INSERT INTO transactions VALUES (?, 90, 70, 11000, '2023-01-04')", (tx_id,)); tx_id+=1

conn.commit()
conn.close()

# Create Buggy Script
buggy_script = """import sqlite3

def find_circular_transactions(db_path, threshold):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # BUG: Implicit cross join, no edge connections!
    query = '''
        SELECT DISTINCT t1.sender_id 
        FROM transactions t1, transactions t2, transactions t3
        WHERE t1.amount > ? AND t2.amount > ? AND t3.amount > ?
    '''

    c.execute(query, (threshold, threshold, threshold))
    results = c.fetchall()
    conn.close()

    return [r[0] for r in results]

if __name__ == '__main__':
    suspects = find_circular_transactions('/home/user/financial_graph.db', 10000)
    with open('/home/user/flagged_entities.csv', 'w') as f:
        for s in sorted(suspects):
            f.write(f"{s}\\n")
"""

with open('/home/user/audit_transactions.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
