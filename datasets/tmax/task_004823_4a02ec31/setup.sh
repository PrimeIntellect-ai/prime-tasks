#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go espeak-ng
    pip3 install pytest

    mkdir -p /app

    # Generate the voicemail audio file
    espeak-ng -w /app/voicemail.wav "The emergency passphrase is epsilon protocol active."

    # Create the SQLite database and populate it
    sqlite3 /app/routing.sqlite <<EOF
CREATE TABLE network_topology (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    node_name TEXT
);
INSERT INTO network_topology (id, parent_id, node_name) VALUES (1, NULL, 'root');
INSERT INTO network_topology (id, parent_id, node_name) VALUES (2, 1, 'node2');
INSERT INTO network_topology (id, parent_id, node_name) VALUES (3, 2, 'node3');
INSERT INTO network_topology (id, parent_id, node_name) VALUES (4, 1, 'node4');
INSERT INTO network_topology (id, parent_id, node_name) VALUES (5, 3, 'node5');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
