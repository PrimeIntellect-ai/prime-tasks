#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/compliancedb-tool-1.2.0/compliancedb
    mkdir -p /home/user

    # Create setup.py
    cat << 'EOF' > /app/compliancedb-tool-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name='compliancedb-tool',
    version='1.2.0',
    packages=find_packages(),
)
EOF

    # Create __init__.py
    touch /app/compliancedb-tool-1.2.0/compliancedb/__init__.py

    # Create aggregator.py
    cat << 'EOF' > /app/compliancedb-tool-1.2.0/compliancedb/aggregator.py
import sqlite3

class Aggregator:
    def __init__(self, db_path):
        self.db_path = db_path

    def get_high_risk_summary(self):
        conn = sqlite3.connect(self.db_path)
        c = conn.cursor()
        # Complex query that takes time without an index
        c.execute("""
            SELECT user_id, SUM(amount)
            FROM transactions
            WHERE risk_score > 8.0
            GROUP BY user_id
        """)
        results = c.fetchall()
        conn.close()
        return [{"user_id": row[0], "total_amount": row[1]} for row in results]
EOF

    # Install the package
    pip3 install -e /app/compliancedb-tool-1.2.0

    # Create the database and populate with 1,000,000 rows
    cat << 'EOF' > /app/generate_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/audit_logs.db')
c = conn.cursor()
c.execute('''CREATE TABLE transactions
             (tx_id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, risk_score REAL, timestamp TEXT)''')

def generate_data():
    for i in range(1000000):
        yield (i, random.randint(1, 10000), random.uniform(10.0, 1000.0), random.uniform(0.0, 10.0), '2023-01-01')

c.executemany('INSERT INTO transactions VALUES (?,?,?,?,?)', generate_data())
conn.commit()
conn.close()
EOF
    python3 /app/generate_db.py
    rm /app/generate_db.py

    # Create run_audit.py
    cat << 'EOF' > /home/user/run_audit.py
import json
import sys
from compliancedb.aggregator import Aggregator

def main():
    agg = Aggregator('/app/audit_logs.db')
    summary = agg.get_high_risk_summary()
    with open('/home/user/audit_summary.json', 'w') as f:
        json.dump(summary, f)

if __name__ == "__main__":
    main()
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
