#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/schema.json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "emp1": {"type": "string"},
      "emp2": {"type": "string"},
      "weight": {"type": "integer"},
      "dept_name": {"type": "string"}
    },
    "required": ["emp1", "emp2", "weight", "dept_name"]
  }
}
EOF

    cat << 'EOF' > /home/user/generate_report.py
import sqlite3
import json
import jsonschema

def generate():
    conn = sqlite3.connect('/home/user/company.db')
    cursor = conn.cursor()

    # BUG: Missing join condition for departments 'd'
    query = """
    SELECT e1.name AS emp1, e2.name AS emp2, c.weight, d.name AS dept_name
    FROM employees e1, employees e2, collaborations c, departments d
    WHERE c.emp_id_1 = e1.id 
      AND c.emp_id_2 = e2.id
      AND e1.dept_id = ?
    """

    cursor.execute(query, (1,))
    rows = cursor.fetchall()

    # Format to list of dicts
    data = []
    for row in rows:
        data.append({
            "emp1": row[0],
            "emp2": row[1],
            "weight": row[2],
            "dept_name": row[3]
        })

    # TODO: Validate against /home/user/schema.json and save to /home/user/report.json
    print(data)

if __name__ == '__main__':
    generate()
EOF

    sqlite3 /home/user/company.db << 'EOF'
CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER);
CREATE TABLE collaborations (emp_id_1 INTEGER, emp_id_2 INTEGER, weight INTEGER);

INSERT INTO departments VALUES (1, 'Engineering'), (2, 'Sales');
INSERT INTO employees VALUES (101, 'Alice', 1), (102, 'Bob', 1), (103, 'Charlie', 2), (104, 'Dave', 1);
INSERT INTO collaborations VALUES (101, 102, 5), (101, 104, 3), (103, 101, 2);
EOF

    chmod -R 777 /home/user
