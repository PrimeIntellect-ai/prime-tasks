#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # Create SQLite DB
    sqlite3 data.db <<EOF
CREATE TABLE departments(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, is_active INTEGER);
INSERT INTO departments VALUES(1, NULL, 'HQ', 1);
INSERT INTO departments VALUES(2, 1, 'Engineering', 1);
INSERT INTO departments VALUES(3, 1, 'Marketing', 1);
INSERT INTO departments VALUES(4, 2, 'Backend', 1);
INSERT INTO departments VALUES(5, 2, 'Frontend', 0);
INSERT INTO departments VALUES(6, 4, 'API', 1);
INSERT INTO departments VALUES(7, 5, 'UI', 1);
CREATE INDEX idx_active ON departments(is_active);
EOF

    # Create sales.json
    cat <<EOF > sales.json
[
  {"tx_id": "t1", "dept_id": 1, "items": [{"price": 10}]},
  {"tx_id": "t2", "dept_id": 2, "items": [{"price": 20}]},
  {"tx_id": "t3", "dept_id": 3, "items": [{"price": 15}, {"price": 15}]},
  {"tx_id": "t4", "dept_id": 4, "items": [{"price": 40}]},
  {"tx_id": "t5", "dept_id": 5, "items": [{"price": 50}]},
  {"tx_id": "t6", "dept_id": 6, "items": [{"price": 60}]},
  {"tx_id": "t7", "dept_id": 7, "items": [{"price": 70}]}
]
EOF

    chmod -R 777 /home/user
