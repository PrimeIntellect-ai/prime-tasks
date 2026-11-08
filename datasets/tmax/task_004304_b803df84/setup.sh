#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    sqlite3 audit.db <<EOF
CREATE TABLE access_logs (
    id INTEGER PRIMARY KEY,
    user_id TEXT,
    doc_id TEXT,
    timestamp DATETIME,
    parent_access_id INTEGER
);

CREATE INDEX idx_timestamp ON access_logs(timestamp);

INSERT INTO access_logs (id, user_id, doc_id, timestamp, parent_access_id) VALUES
(1, 'alice', 'doc_A', '2023-10-01 10:00:00', NULL),
(2, 'bob', 'doc_A', '2023-10-01 10:05:00', 1),
(3, 'charlie', 'doc_B', '2023-10-01 10:10:00', NULL),
(4, 'alice', 'doc_A', '2023-10-01 10:15:00', 2),
(5, 'dave', 'doc_A', '2023-10-01 10:20:00', 4),
(6, 'bob', 'doc_A', '2023-10-01 10:25:00', 4),
(7, 'alice', 'doc_A', '2023-10-01 10:30:00', 5);
EOF

    chmod 644 audit.db

    chmod -R 777 /home/user
