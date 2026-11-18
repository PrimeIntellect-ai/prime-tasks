#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3
    pip3 install pytest

    mkdir -p /home/user

    # Create SQLite DB
    sqlite3 /home/user/data.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
INSERT INTO users (id, name, department) VALUES 
(1, 'Alice', 'HR'),
(2, 'Bob', 'Engineering'),
(3, 'Charlie', 'Engineering'),
(4, 'Diana', 'Marketing'),
(5, 'Eve', 'Sales'),
(6, 'Frank', 'Engineering'),
(7, 'Grace', 'Executive'),
(8, 'Heidi', 'Engineering'),
(9, 'Ivan', 'Sales'),
(10, 'Judy', 'HR');
EOF

    # Create JSON interactions
    cat <<EOF > /home/user/interactions.json
[
  {"src": 1, "dst": 2, "weight": 5},
  {"src": 1, "dst": 5, "weight": 6},
  {"src": 2, "dst": 3, "weight": 8},
  {"src": 4, "dst": 2, "weight": 2},
  {"src": 3, "dst": 6, "weight": 10},
  {"src": 4, "dst": 7, "weight": 12},
  {"src": 5, "dst": 10, "weight": 3},
  {"src": 6, "dst": 8, "weight": 1},
  {"src": 7, "dst": 9, "weight": 15},
  {"src": 8, "dst": 9, "weight": 9}
]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
