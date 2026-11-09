#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest jsonschema

useradd -m -s /bin/bash user || true

# Create the SQLite database and populate it
cat << 'EOF' > /tmp/init.sql
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT, salary INTEGER);
INSERT INTO employees VALUES (1, 'Alice', NULL, 'Executive', 200000);
INSERT INTO employees VALUES (2, 'Bob', 1, 'Engineering', 150000);
INSERT INTO employees VALUES (3, 'Charlie', 1, 'Sales', 120000);
INSERT INTO employees VALUES (4, 'David', 2, 'Engineering', 140000);
INSERT INTO employees VALUES (5, 'Eve', 2, 'Engineering', 140000);
INSERT INTO employees VALUES (6, 'Frank', 3, 'Sales', 90000);
INSERT INTO employees VALUES (7, 'Grace', 3, 'Sales', 95000);
INSERT INTO employees VALUES (8, 'Heidi', 4, 'Engineering', 100000);
EOF

sqlite3 /home/user/company.db < /tmp/init.sql
rm /tmp/init.sql

# Create the schema.json file
cat << 'EOF' > /home/user/schema.json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "id": {"type": "integer"},
      "name": {"type": "string"},
      "department": {"type": "string"},
      "salary": {"type": "integer"},
      "hierarchy_level": {"type": "integer"},
      "dept_total_salary": {"type": "integer"},
      "dept_salary_rank": {"type": "integer"}
    },
    "required": ["id", "name", "department", "salary", "hierarchy_level", "dept_total_salary", "dept_salary_rank"]
  }
}
EOF

chmod -R 777 /home/user
