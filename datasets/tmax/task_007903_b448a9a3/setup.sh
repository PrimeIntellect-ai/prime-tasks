#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = "/home/user/company_data.db"
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute('''
CREATE TABLE employee_events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    emp_id INTEGER,
    manager_id INTEGER,
    salary INTEGER,
    status VARCHAR(20),
    event_timestamp DATETIME
)
''')

# Insert data
events = [
    # Emp 1: CEO
    (1, None, 100000, 'active', '2023-01-01 10:00:00'),
    (1, None, 150000, 'active', '2023-06-01 10:00:00'),

    # Emp 2: VP of Eng
    (2, 1, 90000, 'active', '2023-02-01 10:00:00'),
    (2, 1, 110000, 'active', '2023-07-01 10:00:00'),

    # Emp 3: VP of Sales (Terminated, then re-hired)
    (3, 1, 80000, 'active', '2023-03-01 10:00:00'),
    (3, 1, 80000, 'terminated', '2023-08-01 10:00:00'),
    (3, 1, 120000, 'active', '2023-10-01 10:00:00'),

    # Emp 4: Eng IC (Reports to 2)
    (4, 2, 60000, 'active', '2023-04-01 10:00:00'),
    (4, 2, 70000, 'active', '2023-09-01 10:00:00'),

    # Emp 5: Sales IC (Reports to 3, but terminated later)
    (5, 3, 50000, 'active', '2023-05-01 10:00:00'),
    (5, 3, 50000, 'terminated', '2023-11-01 10:00:00'),

    # Emp 6: Eng IC 2 (Reports to 2)
    (6, 2, 65000, 'active', '2023-05-15 10:00:00')
]

cur.executemany('''
INSERT INTO employee_events (emp_id, manager_id, salary, status, event_timestamp)
VALUES (?, ?, ?, ?, ?)
''', events)

# Create the broken stale table to distract/anchor
cur.execute('''
CREATE TABLE current_employees (
    emp_id INTEGER PRIMARY KEY,
    manager_id INTEGER,
    salary INTEGER
)
''')
cur.execute("INSERT INTO current_employees VALUES (1, NULL, 100000), (2, 1, 90000), (3, 1, 80000), (4, 2, 60000)")

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
