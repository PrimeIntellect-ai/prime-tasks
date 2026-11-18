#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    sqlite3 /home/user/etl_graph.db <<EOF
CREATE TABLE dependencies (
    source TEXT,
    target TEXT
);

INSERT INTO dependencies (source, target) VALUES
('extract_users', 'transform_users'),
('transform_users', 'load_users'),
('extract_orders', 'transform_orders'),
('transform_orders', 'load_orders'),
('load_users', 'aggregate_metrics'),
('load_orders', 'aggregate_metrics'),
('job_X', 'job_Y'),
('job_Y', 'job_Z'),
('job_Z', 'job_X'),
('job_A', 'job_B'),
('job_B', 'job_C'),
('job_C', 'job_B'),
('extract_inventory', 'transform_inventory');
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
