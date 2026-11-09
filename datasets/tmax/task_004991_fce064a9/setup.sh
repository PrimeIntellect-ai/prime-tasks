#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest rdflib

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

db_path = '/home/user/audit_logs.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT)')
c.execute('CREATE TABLE access_events (event_id INTEGER PRIMARY KEY, emp_id INTEGER, system_name TEXT, access_date TEXT)')

employees = [
    (1, 'Alice', 'Finance'),
    (2, 'Bob', 'IT'),
    (3, 'Charlie', 'Finance'),
    (4, 'Diana', 'HR'),
    (5, 'Eve', 'IT')
]
c.executemany('INSERT INTO employees VALUES (?, ?, ?)', employees)

events = [
    (1, 1, 'FIN-01', '2023-10-01'),
    (2, 2, 'FIN-01', '2023-10-02'),
    (3, 1, 'HR-01', '2023-10-03'),
    (4, 3, 'FIN-01', '2023-10-03'),
    (5, 5, 'PRD-DB', '2023-10-04'),
    (6, 2, 'PRD-DB', '2023-10-05'),
    (7, 4, 'HR-01', '2023-10-06'),
    (8, 3, 'PRD-DB', '2023-10-07')
]
c.executemany('INSERT INTO access_events VALUES (?, ?, ?, ?)', events)
conn.commit()
conn.close()

ttl_content = """@prefix ex: <http://example.org/ontology#> .
@prefix sys: <http://example.org/systems/> .

sys:FIN-01 a ex:HighRiskSystem ;
    ex:owner "Finance Dept" .

sys:HR-01 a ex:LowRiskSystem ;
    ex:owner "HR Dept" .

sys:PRD-DB a ex:HighRiskSystem ;
    ex:owner "IT Dept" .
"""
with open('/home/user/system_graph.ttl', 'w') as f:
    f.write(ttl_content)

buggy_script = """import sqlite3
import csv

def generate_report():
    conn = sqlite3.connect('/home/user/audit_logs.db')
    c = conn.cursor()

    # BUG: Implicit cross join. Missing e.id = a.emp_id
    query = '''
    SELECT e.department, a.system_name, COUNT(*) 
    FROM employees e, access_events a 
    WHERE a.system_name = 'FIN-01'
    GROUP BY e.department, a.system_name
    '''

    c.execute(query)
    results = c.fetchall()

    with open('/home/user/compliance_report.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['department', 'system_name', 'access_count'])
        for row in results:
            writer.writerow(row)

if __name__ == '__main__':
    generate_report()
"""
with open('/home/user/generate_report.py', 'w') as f:
    f.write(buggy_script)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
