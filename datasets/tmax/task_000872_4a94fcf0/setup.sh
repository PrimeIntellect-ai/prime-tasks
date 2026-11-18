#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Setup the SQLite database
    sqlite3 /home/user/graph_backup.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, hostname TEXT, region TEXT);
CREATE TABLE edges (source_id INTEGER, target_id INTEGER, latency REAL);

INSERT INTO nodes (id, hostname, region) VALUES 
(1, 'web-us-1', 'US'),
(2, 'db-us-1', 'US'),
(3, 'cache-us-1', 'US'),
(4, 'web-us-2', 'US'),
(5, 'web-eu-1', 'EU'),
(6, 'db-eu-1', 'EU'),
(7, 'cache-eu-1', 'EU');

-- US Connections
INSERT INTO edges (source_id, target_id, latency) VALUES
(1, 2, 5.5),
(1, 3, 2.1),
(1, 4, 1.1),
(2, 3, 1.5),
(2, 4, 3.0),
(4, 1, 10.0);

-- EU Connections
INSERT INTO edges (source_id, target_id, latency) VALUES
(5, 6, 4.0),
(5, 7, 3.5),
(6, 7, 2.0),
(7, 5, 8.0),
(7, 6, 8.5);
EOF

    chmod -R 777 /home/user
