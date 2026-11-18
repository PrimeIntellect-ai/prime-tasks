#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create SQLite DB
    sqlite3 tx_history.db <<EOF
CREATE TABLE transactions (tx_id INTEGER, user_id INTEGER, amount REAL, timestamp TEXT);
INSERT INTO transactions VALUES (101, 1, 500.0, '2023-10-01T10:00:00Z');
INSERT INTO transactions VALUES (99,  1, 1000.0, '2023-10-01T09:00:00Z');
INSERT INTO transactions VALUES (102, 2, 300.0, '2023-10-01T10:05:00Z');
INSERT INTO transactions VALUES (100, 2, 100.0, '2023-10-01T09:05:00Z');
INSERT INTO transactions VALUES (201, 3, 2000.0, '2023-10-01T11:00:00Z');
INSERT INTO transactions VALUES (202, 4, 150.0, '2023-10-01T11:05:00Z');
INSERT INTO transactions VALUES (200, 4, 150.0, '2023-10-01T10:55:00Z');
INSERT INTO transactions VALUES (300, 5, 50.0, '2023-10-01T12:00:00Z');
EOF

    # 2. Create JSONL File
    cat <<EOF > lock_events.jsonl
{"tx_id": 101, "event": "acquire", "resource": "DB_TABLE_USERS"}
{"tx_id": 101, "event": "acquire", "resource": "CACHE_SESSION"}
{"tx_id": 101, "event": "wait", "resource": "DB_TABLE_ORDERS"}
{"tx_id": 102, "event": "acquire", "resource": "DB_TABLE_ORDERS"}
{"tx_id": 102, "event": "wait", "resource": "DB_TABLE_USERS"}
{"tx_id": 201, "event": "acquire", "resource": "REDIS_NODE_1"}
{"tx_id": 202, "event": "acquire", "resource": "REDIS_NODE_2"}
{"tx_id": 202, "event": "wait", "resource": "REDIS_NODE_1"}
{"tx_id": 201, "event": "wait", "resource": "REDIS_NODE_2"}
{"tx_id": 300, "event": "acquire", "resource": "S3_BUCKET"}
EOF

    # 3. Create Graph CSV
    cat <<EOF > wait_graph.csv
101,102
102,101
201,202
202,201
300,99
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
