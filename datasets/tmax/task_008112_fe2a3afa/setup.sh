#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = "/home/user/audit.db"
script_path = "/home/user/audit_pipeline.py"

# 1. Create SQLite DB
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT)''')
c.execute('''CREATE TABLE communications (sender_id INTEGER, receiver_id INTEGER, timestamp DATETIME)''')

employees = [
    (1, 'Alice', 'Sales'), (2, 'Bob', 'Sales'), (3, 'Charlie', 'Sales'), (4, 'Diana', 'Sales'), (5, 'Eve', 'Sales'),
    (6, 'Frank', 'IT'), (7, 'Grace', 'IT'), (8, 'Heidi', 'IT'), (9, 'Ivan', 'IT'), (10, 'Judy', 'IT'),
    (11, 'Mallory', 'HR'), (12, 'Niaj', 'HR'), (13, 'Olivia', 'HR'), (14, 'Peggy', 'HR'), (15, 'Sybil', 'HR'),
    (16, 'Trent', 'Finance'), (17, 'Victor', 'Finance'), (18, 'Walter', 'Finance'), (19, 'Xenia', 'Finance'), (20, 'Yvonne', 'Finance')
]
c.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)

communications = [
    (1, 2), (2, 3), (3, 4), (4, 5), (5, 1), (3, 1),
    (6, 7), (7, 8), (9, 8), (10, 8), (8, 6),
    (11, 12), (12, 13), (13, 14), (14, 15), (15, 11),
    (16, 17), (17, 18), (18, 19), (19, 20), (20, 16),
    (3, 8), (4, 8), (8, 12), (8, 15), (15, 18), (8, 16)
]

extra_comms = [
    (3, 4), (3, 1), (3, 8), (3, 2), 
    (8, 6), (8, 12), (8, 15), (8, 16), (8, 7), 
    (15, 11), (15, 18), (15, 12), 
    (18, 19), (18, 16), (18, 20) 
]
all_comms = communications + extra_comms

for sender, receiver in all_comms:
    c.execute("INSERT INTO communications (sender_id, receiver_id, timestamp) VALUES (?, ?, '2023-10-01 10:00:00')", (sender, receiver))

conn.commit()
conn.close()

# 2. Write the buggy Python script
buggy_code = """import sqlite3
import csv

def run_audit():
    conn = sqlite3.connect('/home/user/audit.db')
    cursor = conn.cursor()

    # BUG: Implicit cross join between e1 and e2, missing join conditions, wrong grouping.
    buggy_sql = '''
        SELECT e1.department, e1.id, COUNT(c.sender_id) as message_count
        FROM employees e1, employees e2, communications c
        GROUP BY e1.department
    '''

    cursor.execute(buggy_sql)
    results = cursor.fetchall()

    with open('/home/user/top_communicators.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['department', 'employee_id', 'message_count'])
        writer.writerows(results)

    print("Phase 1 complete. Data written to top_communicators.csv")

    # TODO: Implement Phase 2 (Centrality) and Phase 3 (Shortest Path)

if __name__ == "__main__":
    run_audit()
"""

with open(script_path, "w") as f:
    f.write(buggy_code)

os.chmod(script_path, 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
