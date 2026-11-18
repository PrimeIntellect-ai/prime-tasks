#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup.py
import sqlite3
import random
import json
from datetime import datetime, timedelta

# Create DB
conn = sqlite3.connect('/home/user/company.db')
c = conn.cursor()

c.execute('''CREATE TABLE departments (dept_id INTEGER PRIMARY KEY, dept_name TEXT)''')
c.execute('''CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, emp_name TEXT, dept_id INTEGER, hire_date TEXT)''')
c.execute('''CREATE TABLE salaries (emp_id INTEGER, amount REAL, effective_date TEXT)''')

# Insert data
depts = ['Engineering', 'Sales', 'Marketing', 'HR', 'Finance']
for i, d in enumerate(depts):
    c.execute("INSERT INTO departments VALUES (?, ?)", (i+1, d))

start_date = datetime(2015, 1, 1)
for i in range(1, 10001):
    dept_id = random.randint(1, 5)
    hd = start_date + timedelta(days=random.randint(0, 3000))
    c.execute("INSERT INTO employees VALUES (?, ?, ?, ?)", (i, f"Employee_{i}", dept_id, hd.strftime('%Y-%m-%d')))

    # 3 salary records per employee
    for j in range(3):
        amt = random.uniform(50000, 150000)
        sd = hd + timedelta(days=j*365)
        c.execute("INSERT INTO salaries VALUES (?, ?, ?)", (i, amt, sd.strftime('%Y-%m-%d')))

conn.commit()
conn.close()
EOF

    python3 setup.py
    rm setup.py

    cat << 'EOF' > /home/user/queries.sql
SELECT d.dept_name, AVG(s.amount) FROM employees e JOIN salaries s ON e.emp_id = s.emp_id JOIN departments d ON e.dept_id = d.dept_id GROUP BY d.dept_name;
SELECT emp_name FROM employees WHERE hire_date > '2022-01-01';
SELECT e.emp_name, s.amount FROM employees e JOIN salaries s ON e.emp_id = s.emp_id WHERE s.amount > 140000;
EOF

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "query_id": {
        "type": "string",
        "pattern": "^query_[0-9]+$"
      },
      "row_count": {
        "type": "integer",
        "minimum": 0
      },
      "execution_time_ms": {
        "type": "number",
        "minimum": 0
      }
    },
    "required": ["query_id", "row_count", "execution_time_ms"],
    "additionalProperties": false
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
