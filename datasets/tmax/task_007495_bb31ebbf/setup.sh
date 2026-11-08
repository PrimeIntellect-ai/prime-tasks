#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/infrastructure.db <<EOF
CREATE TABLE users (uid INTEGER PRIMARY KEY, username TEXT);
CREATE TABLE assets (asset_id INTEGER PRIMARY KEY, hostname TEXT, classification TEXT);
CREATE TABLE connections (from_asset INTEGER, to_asset INTEGER);
CREATE TABLE access_events (event_id INTEGER PRIMARY KEY, uid INTEGER, asset_id INTEGER, event_time DATETIME);

INSERT INTO users VALUES (1, 'alice'), (2, 'bob'), (3, 'charlie');

-- Assets
INSERT INTO assets VALUES (101, 'jump-01', 'Public');
INSERT INTO assets VALUES (102, 'proxy-01', 'Internal');
INSERT INTO assets VALUES (103, 'db-master', 'Restricted');
INSERT INTO assets VALUES (104, 'jump-02', 'Public');
INSERT INTO assets VALUES (105, 'db-replica', 'Restricted');

-- Connections
INSERT INTO connections VALUES (101, 102);
INSERT INTO connections VALUES (102, 103);
INSERT INTO connections VALUES (104, 105);
INSERT INTO connections VALUES (101, 104);

-- Access Events
INSERT INTO access_events VALUES (1, 1, 101, '2023-10-01 10:00:00');
INSERT INTO access_events VALUES (2, 1, 101, '2023-10-01 14:00:00');
INSERT INTO access_events VALUES (3, 2, 101, '2023-10-02 09:00:00');
INSERT INTO access_events VALUES (4, 1, 104, '2023-10-02 10:00:00');
EOF

    chmod -R 777 /home/user
