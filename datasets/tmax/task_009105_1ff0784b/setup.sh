#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite DB
    sqlite3 logistics.db <<EOF
CREATE TABLE hubs (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE routes (id INTEGER PRIMARY KEY, src_hub INTEGER, dst_hub INTEGER, distance REAL);
CREATE TABLE deliveries (id INTEGER PRIMARY KEY, route_id INTEGER, duration_hours REAL);

INSERT INTO hubs VALUES (1, 'HubA'), (2, 'HubB'), (3, 'HubC'), (4, 'HubD'), (5, 'HubE');
INSERT INTO routes VALUES (1, 1, 3, 150.5), (2, 3, 4, 200.0), (3, 1, 2, 50.0), (4, 2, 4, 120.0), (5, 4, 5, 300.0), (6, 3, 5, 100.0);
INSERT INTO deliveries VALUES (1, 1, 90.0), (2, 2, 110.0), (3, 3, 40.0), (4, 4, 105.0), (5, 5, 150.0), (6, 6, 80.0);
EOF

    # Create JSONL events
    cat <<EOF > events.jsonl
{"hub_id": 1, "event": "processing", "time_spent": 12.5}
{"hub_id": 1, "event": "processing", "time_spent": 11.5}
{"hub_id": 2, "event": "processing", "time_spent": 5.0}
{"hub_id": 3, "event": "processing", "time_spent": 14.0}
{"hub_id": 3, "event": "processing", "time_spent": 16.0}
{"hub_id": 4, "event": "processing", "time_spent": 10.5}
{"hub_id": 5, "event": "processing", "time_spent": 8.0}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
