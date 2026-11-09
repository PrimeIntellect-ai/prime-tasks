#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    cat << 'EOF' > schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "id": { "type": "integer" },
    "name": { "type": "string" },
    "role": { "type": "string" },
    "subordinates": {
      "type": "array",
      "items": { "$ref": "#" }
    }
  },
  "required": ["id", "name", "role", "subordinates"]
}
EOF

    sqlite3 company.db << 'EOF'
CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER,
    role TEXT
);

CREATE TABLE hierarchy_cache (
    id INTEGER PRIMARY KEY,
    path TEXT
);

INSERT INTO employees (id, name, manager_id, role) VALUES 
(1, 'Alice', NULL, 'CEO'),
(2, 'Bob', 1, 'VP Engineering'),
(3, 'Charlie', 1, 'VP Sales'),
(4, 'Dave', 2, 'Backend Lead'),
(5, 'Eve', 2, 'Frontend Lead'),
(6, 'Frank', 4, 'Software Engineer'),
(7, 'Grace', 3, 'Account Executive');

INSERT INTO hierarchy_cache VALUES (1, '/1'), (2, '/1/2'), (3, '/1/8');
EOF

    go mod init etl_project
    go get github.com/mattn/go-sqlite3

    chmod -R 777 /home/user
