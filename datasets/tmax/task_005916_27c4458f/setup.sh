#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import sqlite3
import json

os.makedirs('/home/user/data', exist_ok=True)

# Create SQLite DB
conn = sqlite3.connect('/home/user/data/org.db')
c = conn.cursor()
c.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)')
c.executemany('INSERT INTO employees (id, name, manager_id) VALUES (?, ?, ?)', [
    (1, 'Alice', None),
    (2, 'Bob', 1),
    (3, 'Charlie', 1),
    (4, 'Dave', 2),
    (5, 'Eve', 4),
    (6, 'Frank', 2),
    (7, 'Grace', None), # Isolated contractor, not under Alice
    (8, 'Hank', 7)
])
conn.commit()
conn.close()

# Create JSON file
tasks_data = [
    {
        "id": "t1", 
        "assignee": 1, 
        "subtasks": [
            {
                "id": "t1.1", 
                "assignee": 2, 
                "subtasks": []
            },
            {
                "id": "t1.2", 
                "assignee": 4, 
                "subtasks": [
                    {
                        "id": "t1.2.1", 
                        "assignee": 5, 
                        "subtasks": []
                    }
                ]
            }
        ]
    },
    {
        "id": "t2", 
        "assignee": 3, 
        "subtasks": []
    },
    {
        "id": "t3", 
        "assignee": 5, 
        "subtasks": []
    },
    {
        "id": "t4", 
        "assignee": 7, 
        "subtasks": [
            {
                "id": "t4.1",
                "assignee": 8,
                "subtasks": []
            }
        ]
    }
]

with open('/home/user/data/tasks.json', 'w') as f:
    json.dump(tasks_data, f)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
