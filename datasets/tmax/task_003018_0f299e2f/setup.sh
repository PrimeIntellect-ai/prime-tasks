#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup

    sqlite3 /home/user/backup/relational.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE transactions (tx_id TEXT PRIMARY KEY, user_id INTEGER, amount REAL, status TEXT, created_at DATETIME);
INSERT INTO users (id, name) VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'David'), (5, 'Eve');
INSERT INTO transactions (tx_id, user_id, amount, status, created_at) VALUES 
('tx101', 1, 50.0, 'COMPLETED', '2023-10-01 10:00:00'),
('tx102', 2, 20.0, 'COMPLETED', '2023-10-01 11:00:00'),
('tx103', 3, 15.0, 'PENDING', '2023-10-01 12:00:00');
EOF

    cat <<EOF > /home/user/backup/documents.json
[
  {"user_id": 1, "preferences": {"theme": "dark"}, "last_tx_id": "tx101"},
  {"user_id": 2, "preferences": {"theme": "light"}, "last_tx_id": "tx104"}, 
  {"user_id": 3, "preferences": "invalid_type", "last_tx_id": "tx103"},
  {"user_id": 4, "preferences": {"theme": "dark"}, "last_tx_id": "invalid_format"},
  {"user_id": 5, "last_tx_id": "tx105"}
]
EOF

    cat <<EOF > /home/user/backup/graph.csv
sender_id,receiver_id,tx_id
1,2,tx101
2,3,tx102
3,4,tx104
4,5,tx105
EOF

    chmod -R 777 /home/user
