#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/telemetry.db <<EOF
CREATE TABLE nodes (node_id INTEGER PRIMARY KEY, status TEXT, region TEXT);
CREATE TABLE telemetry (id INTEGER PRIMARY KEY, node_id INTEGER, ts DATETIME, metric REAL);
CREATE INDEX idx_telemetry_node ON telemetry(node_id);

INSERT INTO nodes VALUES (1, 'ACTIVE', 'us-east');
INSERT INTO nodes VALUES (2, 'INACTIVE', 'us-east');
INSERT INTO nodes VALUES (3, 'ACTIVE', 'us-west');
INSERT INTO nodes VALUES (4, 'ACTIVE', 'us-east');

INSERT INTO telemetry VALUES (101, 1, '2023-10-01T10:00:00Z', 99.5);
INSERT INTO telemetry VALUES (102, 1, '2023-10-01T10:05:00Z', 98.2);
INSERT INTO telemetry VALUES (103, 2, '2023-10-01T10:00:00Z', 50.0);
INSERT INTO telemetry VALUES (104, 3, '2023-10-01T10:00:00Z', 88.8);
INSERT INTO telemetry VALUES (105, 4, '2023-10-01T10:15:00Z', 91.1);
EOF

    chmod -R 777 /home/user
