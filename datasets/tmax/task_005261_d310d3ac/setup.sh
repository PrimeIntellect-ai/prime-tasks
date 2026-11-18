#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    sqlite3 /home/user/graph.db <<EOF
CREATE TABLE components (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    name TEXT,
    base_cost INTEGER,
    type TEXT
);

INSERT INTO components (id, parent_id, name, base_cost, type) VALUES
(1, NULL, 'Core', 100, 'System'),
(2, 1, 'Module A', 50, 'Module'),
(3, 1, 'Module B', 60, 'Module'),
(4, 2, 'Sub A1', 20, 'Submodule'),
(5, 2, 'Sub A2', 30, 'Submodule'),
(6, 3, 'Sub B1', 40, 'Submodule'),
(7, 3, 'Sub B2', 10, 'Submodule');
EOF

    chmod -R 777 /home/user
