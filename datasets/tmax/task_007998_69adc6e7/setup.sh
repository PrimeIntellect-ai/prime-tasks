#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup SQLite database
    sqlite3 /home/user/etl_data.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, signup_date TEXT);
CREATE TABLE purchases (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, purchase_date TEXT);

INSERT INTO users (id, name, signup_date) VALUES 
(1, 'Alice', '2023-01-05'), 
(2, 'Bob', '2023-02-10'),
(3, 'Charlie', '2023-01-20');

INSERT INTO purchases (id, user_id, amount, purchase_date) VALUES 
(101, 1, 50.0, '2023-01-15'), 
(102, 1, 25.0, '2023-02-01'), 
(103, 2, 100.0, '2023-02-15'),
(104, 3, 75.0, '2023-01-25');
EOF

    # Create broken Python script
    cat << 'EOF' > /home/user/broken_etl.py
import sqlite3
import sys
import csv

if len(sys.argv) != 3:
    print("Usage: python broken_etl.py <signup_date> <purchase_date>")
    sys.exit(1)

signup_date = sys.argv[1]
purchase_date = sys.argv[2]

conn = sqlite3.connect('/home/user/etl_data.db')
cursor = conn.cursor()

# BUG: Implicit cross join and string formatting
query = f"""
SELECT u.name, p.amount, p.purchase_date 
FROM users u, purchases p 
WHERE u.signup_date >= '{signup_date}' 
  AND p.purchase_date >= '{purchase_date}'
"""

cursor.execute(query)
rows = cursor.fetchall()

with open('/home/user/output.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['name', 'amount', 'purchase_date'])
    writer.writerows(rows)

conn.close()
EOF

    chmod -R 777 /home/user
