#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    sqlite3 etl_graph.db <<EOF
CREATE TABLE tasks (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE dependencies (source_id INTEGER, target_id INTEGER);

INSERT INTO tasks (id, name) VALUES 
(1, 'extract_users'),
(2, 'extract_orders'),
(3, 'transform_users'),
(4, 'transform_orders'),
(5, 'join_data'),
(6, 'aggregate_metrics'),
(7, 'load_warehouse'),
(8, 'generate_reports'),
(9, 'send_alerts');

INSERT INTO dependencies (source_id, target_id) VALUES 
(1, 3),
(2, 4),
(3, 5),
(4, 5),
(5, 6),
(6, 7),
(7, 8),
(7, 9);
EOF

    chmod -R 777 /home/user
