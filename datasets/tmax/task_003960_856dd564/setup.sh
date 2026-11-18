#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest pandas

    mkdir -p /app /home/user
    cd /app

    # Create the C source for the binary
    cat << 'EOF' > risk_scorer.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    long amount = atol(argv[1]);
    double score = (amount * 137 % 1000) / 1000.0;
    if (amount > 5000) score += 0.5;
    printf("%.3f\n", score);
    return 0;
}
EOF
    gcc -O2 risk_scorer.c -o risk_scorer
    strip risk_scorer
    rm risk_scorer.c

    # Create the Database and Corrupt the Index
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/financial_audit.db')
c = conn.cursor()

c.execute('''CREATE TABLE departments (department_id INTEGER PRIMARY KEY, name TEXT)''')
c.execute('''CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, department_id INTEGER, amount INTEGER, parent_tx_id INTEGER, timestamp INTEGER)''')

departments = [(1, 'Sales'), (2, 'Engineering')]
c.executemany("INSERT INTO departments VALUES (?, ?)", departments)

# Insert valid transactions
txs = [
    (1, 1, 1000, None, 1600000000),
    (2, 1, 1500, 1,    1600000010),
    (3, 2, 2000, None, 1600000020),
    (4, 1, 3000, 2,    1600000030),
    (5, 2, 4000, 3,    1600000040)
]
c.executemany("INSERT INTO transactions VALUES (?, ?, ?, ?, ?)", txs)

# Create an index
c.execute("CREATE INDEX idx_parent ON transactions(parent_tx_id)")
conn.commit()

# Deliberately corrupt the index by modifying the sqlite_master and deleting pages (simulated via writable_schema)
c.execute("PRAGMA writable_schema = ON")
c.execute("UPDATE sqlite_master SET sql = 'CREATE INDEX idx_parent ON transactions(amount)' WHERE name = 'idx_parent'")
c.execute("PRAGMA writable_schema = OFF")
conn.commit()
conn.close()
EOF
    python3 /tmp/setup_db.py

    # Create the Verification Script
    cat << 'EOF' > /tmp/evaluate.py
import pandas as pd
import sys

def evaluate():
    try:
        agent_df = pd.read_csv('/home/user/compliance_report.csv')

        # Ground truth data
        expected_data = [
            {'tx_id': 1, 'root_tx_id': 1, 'department_id': 1, 'running_total': 1000, 'risk_score': 0.0},
            {'tx_id': 2, 'root_tx_id': 1, 'department_id': 1, 'running_total': 2500, 'risk_score': 0.5},
            {'tx_id': 4, 'root_tx_id': 1, 'department_id': 1, 'running_total': 5500, 'risk_score': 0.5},
            {'tx_id': 3, 'root_tx_id': 3, 'department_id': 2, 'running_total': 2000, 'risk_score': 0.0},
            {'tx_id': 5, 'root_tx_id': 3, 'department_id': 2, 'running_total': 6000, 'risk_score': 1.0}
        ]

        # Calculate expected scores using the algorithm
        for row in expected_data:
            amt = row['running_total']
            score = (amt * 137 % 1000) / 1000.0
            if amt > 5000:
                score += 0.5
            row['risk_score'] = round(score, 3)

        expected_df = pd.DataFrame(expected_data)

        if len(agent_df) != len(expected_df):
            print(0.0)
            return

        # Check match
        matches = 0
        for i in range(len(expected_df)):
            if (agent_df.iloc[i]['tx_id'] == expected_df.iloc[i]['tx_id'] and
                agent_df.iloc[i]['root_tx_id'] == expected_df.iloc[i]['root_tx_id'] and
                agent_df.iloc[i]['department_id'] == expected_df.iloc[i]['department_id'] and
                agent_df.iloc[i]['running_total'] == expected_df.iloc[i]['running_total'] and
                abs(agent_df.iloc[i]['risk_score'] - expected_df.iloc[i]['risk_score']) < 0.01):
                matches += 1

        accuracy = matches / len(expected_df)
        print(accuracy)
    except Exception as e:
        print(0.0)

if __name__ == "__main__":
    evaluate()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
