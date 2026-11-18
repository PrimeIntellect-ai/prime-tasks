#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    sqlite3 users.db <<EOF
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    username TEXT,
    is_active INTEGER
);
INSERT INTO users (user_id, username, is_active) VALUES (1, 'alice', 1);
INSERT INTO users (user_id, username, is_active) VALUES (2, 'bob', 0);
INSERT INTO users (user_id, username, is_active) VALUES (3, 'charlie', 1);
INSERT INTO users (user_id, username, is_active) VALUES (4, 'dave', 1);
EOF

    # Create events.jsonl
    cat <<EOF > events.jsonl
{"user_id": 1, "timestamp": "2023-10-01T10:00:00Z", "points": 10}
{"user_id": 1, "timestamp": "2023-10-01T10:05:00Z", "points": 15}
{"user_id": 2, "timestamp": "2023-10-01T10:06:00Z", "points": 500}
{"user_id": 1, "timestamp": "2023-10-01T10:10:00Z", "points": 5}
{"user_id": 1, "timestamp": "2023-10-01T10:15:00Z", "points": 20}
{"user_id": 3, "timestamp": "2023-10-02T11:00:00Z", "points": 5}
{"user_id": 4, "timestamp": "2023-10-03T09:00:00Z", "points": 100}
{"user_id": 4, "timestamp": "2023-10-03T09:05:00Z", "points": -50}
{"user_id": 4, "timestamp": "2023-10-03T09:10:00Z", "points": 200}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
