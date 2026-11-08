#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific dependencies
    apt-get install -y sqlite3 libsqlite3-dev g++

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the initial database
    sqlite3 /home/user/graph_data.db <<EOF
CREATE TABLE edges (
    id INTEGER PRIMARY KEY,
    source INTEGER,
    target INTEGER,
    weight REAL,
    recorded_at INTEGER
);

INSERT INTO edges (source, target, weight, recorded_at) VALUES (1, 2, 5.0, 100);
INSERT INTO edges (source, target, weight, recorded_at) VALUES (1, 2, 12.0, 200);
INSERT INTO edges (source, target, weight, recorded_at) VALUES (2, 3, 15.0, 150);
INSERT INTO edges (source, target, weight, recorded_at) VALUES (3, 4, 20.0, 50);
INSERT INTO edges (source, target, weight, recorded_at) VALUES (3, 4, 9.0, 300);
INSERT INTO edges (source, target, weight, recorded_at) VALUES (4, 1, 11.0, 100);
EOF

    chown user:user /home/user/graph_data.db

    # Ensure permissions are open
    chmod -R 777 /home/user
