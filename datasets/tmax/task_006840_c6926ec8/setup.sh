#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = '/home/user/compliance.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''
CREATE TABLE entities (
    id INTEGER PRIMARY KEY,
    name TEXT,
    domain TEXT
)
''')

cursor.execute('''
CREATE TABLE transactions (
    tx_id INTEGER PRIMARY KEY,
    source_id INTEGER,
    target_id INTEGER,
    amount REAL,
    tx_date TEXT
)
''')

entities_data = [
    (1, 'Alice', 'Internal'),
    (2, 'Bob', 'External'),
    (3, 'Charlie', 'Internal'),
    (4, 'Dave', 'External'),
    (5, 'Eve', 'Internal'),
    (6, 'Frank', 'External')
]

transactions_data = [
    (1, 1, 2, 100, '2023-01-01'),
    (2, 2, 3, 200, '2023-01-02'),
    (3, 2, 4, 50, '2023-01-03'),
    (4, 3, 4, 150, '2023-01-04'),
    (5, 4, 1, 300, '2023-01-05'),
    (6, 4, 5, 100, '2023-01-06'),
    (7, 5, 6, 80, '2023-01-07'),
    (8, 6, 5, 50, '2023-01-08'),
    (9, 6, 1, 50, '2023-01-09')
]

cursor.executemany('INSERT INTO entities VALUES (?, ?, ?)', entities_data)
cursor.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', transactions_data)
conn.commit()
conn.close()

buggy_script = """import sqlite3
import csv

def run_audit():
    conn = sqlite3.connect('/home/user/compliance.db')
    cursor = conn.cursor()

    # BUGGY QUERY: Missing join condition between t1 and t2, resulting in a cross join.
    # Also doesn't properly calculate the average outgoing amount.
    query = '''
    SELECT 
        e1.name as A_name, 
        e2.name as B_name, 
        e3.name as C_name, 
        t1.amount as t1_amount, 
        t2.amount as t2_amount
    FROM entities e1, transactions t1, entities e2, transactions t2, entities e3
    WHERE e1.id = t1.source_id
      AND e2.id = t1.target_id
      AND e3.id = t2.target_id
      AND e1.domain = e3.domain
      AND e1.domain != e2.domain
      AND t2.amount > 100
    '''

    cursor.execute(query)
    results = cursor.fetchall()

    with open('/home/user/flagged_paths.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['A_name', 'B_name', 'C_name', 't1_amount', 't2_amount'])
        writer.writerows(results)

if __name__ == '__main__':
    run_audit()
"""

with open('/home/user/audit.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
