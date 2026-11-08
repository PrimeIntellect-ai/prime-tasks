#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    sqlite3 data.db <<EOF
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, region TEXT);
CREATE TABLE events (id INTEGER PRIMARY KEY, user_id INTEGER, event_type TEXT, event_time DATETIME);

INSERT INTO users (id, name, region) VALUES (1, 'Alice', 'NA');
INSERT INTO users (id, name, region) VALUES (2, 'Bob', 'EU');
INSERT INTO users (id, name, region) VALUES (3, 'Charlie', 'NA');
INSERT INTO users (id, name, region) VALUES (4, 'Diana', 'EU');

INSERT INTO events (id, user_id, event_type, event_time) VALUES (1, 1, 'login', '2023-01-01 10:00:00');
INSERT INTO events (id, user_id, event_type, event_time) VALUES (2, 1, 'click', '2023-01-01 10:05:00');
INSERT INTO events (id, user_id, event_type, event_time) VALUES (3, 1, 'logout', '2023-01-01 10:10:00');
INSERT INTO events (id, user_id, event_type, event_time) VALUES (4, 2, 'login', '2023-01-01 11:00:00');
INSERT INTO events (id, user_id, event_type, event_time) VALUES (5, 3, 'login', '2023-01-01 12:00:00');
INSERT INTO events (id, user_id, event_type, event_time) VALUES (6, 3, 'purchase', '2023-01-01 12:15:00');
INSERT INTO events (id, user_id, event_type, event_time) VALUES (7, 4, 'login', '2023-01-01 13:00:00');
INSERT INTO events (id, user_id, event_type, event_time) VALUES (8, 4, 'click', '2023-01-01 13:05:00');
EOF

    cat <<EOF > plan.txt
QUERY PLAN
|--SCAN TABLE users
\`--SEARCH TABLE events USING AUTOMATIC COVERING INDEX (user_id=?)
EOF

    chmod -R 777 /home/user
