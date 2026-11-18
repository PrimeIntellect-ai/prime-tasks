#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/etl_data.db <<EOF
CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT, env TEXT);
CREATE TABLE connections_raw (source_id INTEGER, target_id INTEGER, updated_at INTEGER, status TEXT);

INSERT INTO servers (id, hostname, env) VALUES
(1, 'web-prod-01', 'prod'),
(2, 'db-prod-01', 'prod'),
(3, 'cache-prod-01', 'prod'),
(4, 'web-dev-01', 'dev');

INSERT INTO connections_raw VALUES (1, 2, 1000, 'active');
INSERT INTO connections_raw VALUES (1, 2, 1100, 'inactive');
INSERT INTO connections_raw VALUES (1, 2, 1200, 'active');

INSERT INTO connections_raw VALUES (1, 3, 1000, 'active');
INSERT INTO connections_raw VALUES (1, 3, 1300, 'inactive');

INSERT INTO connections_raw VALUES (1, 4, 1050, 'active');

INSERT INTO connections_raw VALUES (2, 3, 900, 'active');

INSERT INTO connections_raw VALUES (4, 2, 2000, 'active');
EOF

    chmod -R 777 /home/user
