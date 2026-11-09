#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import os

os.makedirs("/home/user", exist_ok=True)

# 1. Create org_graph.ttl
ttl_content = """
@prefix ex: <http://example.org/> .

ex:Alice ex:manages ex:Bob .
ex:Alice ex:manages ex:Charlie .
ex:Bob ex:manages ex:David .
ex:David ex:manages ex:Frank .
ex:Eve ex:manages ex:Grace .
"""
with open("/home/user/org_graph.ttl", "w") as f:
    f.write(ttl_content)

# 2. Create sales.db
conn = sqlite3.connect('/home/user/sales.db')
c = conn.cursor()
c.execute('''CREATE TABLE transactions (id INTEGER PRIMARY KEY, employee_name TEXT, sale_date DATE, amount REAL)''')

# Insert data
data = [
    # Alice
    (1, 'Alice', '2023-10-01', 100.0),
    (2, 'Alice', '2023-10-02', 150.0),
    (3, 'Alice', '2023-10-03', 200.0), # Rolling avg: 150.0
    # Bob
    (4, 'Bob', '2023-10-01', 50.0),
    (5, 'Bob', '2023-10-02', 70.0), # Rolling avg: 60.0
    # Charlie
    (6, 'Charlie', '2023-10-01', 300.0),
    (7, 'Charlie', '2023-10-03', 300.0),
    (8, 'Charlie', '2023-10-05', 300.0), # Rolling avg: 300.0
    # David
    (9, 'David', '2023-10-01', 10.0),
    (10, 'David', '2023-10-02', 20.0),
    (11, 'David', '2023-10-03', 30.0),
    (12, 'David', '2023-10-04', 40.0), # Rolling avg (last 3): (20+30+40)/3 = 30.0
    # Frank
    (13, 'Frank', '2023-10-01', 100.0), # Rolling avg: 100.0
    # Eve (Not in subgraph)
    (14, 'Eve', '2023-10-01', 999.0)
]

c.executemany("INSERT INTO transactions VALUES (?, ?, ?, ?)", data)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
