#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    python3 -c "
import sqlite3
import json
import os
import random

schema = {
    'type': 'object',
    'properties': {
        'suspect_id': {'type': 'integer'},
        'suspect_name': {'type': 'string'},
        'department': {'type': 'string'},
        'access_count': {'type': 'integer'},
        'management_path': {
            'type': 'array',
            'items': {'type': 'string'}
        }
    },
    'required': ['suspect_id', 'suspect_name', 'department', 'access_count', 'management_path'],
    'additionalProperties': False
}
with open('/home/user/schema.json', 'w') as f:
    json.dump(schema, f, indent=2)

conn = sqlite3.connect('/home/user/employees.db')
cursor = conn.cursor()
cursor.execute('CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)')
cursor.execute('CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, dept_id INTEGER)')

departments = [(10, 'Executive'), (20, 'Engineering'), (30, 'Sales')]
cursor.executemany('INSERT INTO departments VALUES (?, ?)', departments)

employees = [
    (1, 'Alice', None, 10),
    (2, 'Bob', 1, 20),
    (3, 'Charlie', 2, 20),
    (4, 'Dave', 3, 20),
    (5, 'Eve', 1, 30)
]
cursor.executemany('INSERT INTO employees VALUES (?, ?, ?, ?)', employees)
conn.commit()
conn.close()

logs = []
for _ in range(15):
    logs.append({'emp_id': 4, 'doc_id': 'DOC-999', 'timestamp': '2023-10-01T10:00:00Z'})
for _ in range(3):
    logs.append({'emp_id': 5, 'doc_id': 'DOC-999', 'timestamp': '2023-10-01T11:00:00Z'})
for _ in range(20):
    logs.append({'emp_id': 2, 'doc_id': 'DOC-111', 'timestamp': '2023-10-01T09:00:00Z'})

random.shuffle(logs)

with open('/home/user/access_logs.jsonl', 'w') as f:
    for log in logs:
        f.write(json.dumps(log) + '\n')
"

    chmod -R 777 /home/user
