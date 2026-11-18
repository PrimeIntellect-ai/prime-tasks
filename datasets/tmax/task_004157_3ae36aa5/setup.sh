#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3 build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE sales (id INTEGER PRIMARY KEY, emp_id INTEGER, amount REAL, sale_date TEXT);

INSERT INTO employees (id, name, manager_id) VALUES 
(1, 'Alice (CEO)', NULL),
(2, 'Bob (VP)', 1),
(3, 'Charlie (VP)', 1),
(4, 'Dave (Dev)', 2),
(5, 'Eve (Dev)', 2),
(6, 'Frank (Dev)', 3);

INSERT INTO sales (emp_id, amount, sale_date) VALUES 
(1, 0, '2023-01-01'),
(2, 100, '2023-01-01'),
(3, 200, '2023-01-01'),
(4, 50, '2023-01-01'),
(5, 150, '2023-01-01'),
(6, 300, '2023-01-01');
EOF

    cat << 'EOF' > /home/user/schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "emp_id": { "type": "integer" },
      "name": { "type": "string" },
      "team_sales": { "type": "number" },
      "peer_rank": { "type": "integer" }
    },
    "required": ["emp_id", "name", "team_sales", "peer_rank"],
    "additionalProperties": false
  }
}
EOF

    chmod -R 777 /home/user
