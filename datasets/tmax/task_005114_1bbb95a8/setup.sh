#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    sqlite3 /home/user/backups.db << 'EOF'
CREATE TABLE topology (source_node TEXT, target_node TEXT);
INSERT INTO topology VALUES
('db-main', 'san-local-1'),
('db-main', 'san-local-2'),
('san-local-1', 'cloud-bucket-A'),
('cloud-bucket-A', 'cold-glacier-A'),
('san-local-2', 'cloud-bucket-B'),
('db-other', 'san-local-3');

CREATE TABLE jobs (job_id TEXT, node TEXT, run_date TEXT, size_mb REAL, status TEXT);
INSERT INTO jobs VALUES
-- db-main jobs
('j101', 'db-main', '2023-10-01T00:00:00Z', 100.0, 'SUCCESS'),
('j102', 'db-main', '2023-10-02T00:00:00Z', 105.0, 'SUCCESS'),
('j103', 'db-main', '2023-10-03T00:00:00Z', 102.0, 'SUCCESS'),
('j104', 'db-main', '2023-10-04T00:00:00Z', 104.0, 'SUCCESS'),

-- cloud-bucket-A jobs (Anomaly here!)
('j201', 'cloud-bucket-A', '2023-10-01T02:00:00Z', 100.0, 'SUCCESS'),
('j202', 'cloud-bucket-A', '2023-10-02T02:00:00Z', 105.0, 'SUCCESS'),
('j203', 'cloud-bucket-A', '2023-10-03T02:00:00Z', 102.0, 'SUCCESS'),
('j204', 'cloud-bucket-A', '2023-10-04T02:00:00Z', 250.0, 'SUCCESS'),

-- cloud-bucket-B jobs (No anomaly)
('j301', 'cloud-bucket-B', '2023-10-01T02:00:00Z', 100.0, 'SUCCESS'),
('j302', 'cloud-bucket-B', '2023-10-02T02:00:00Z', 105.0, 'SUCCESS'),
('j303', 'cloud-bucket-B', '2023-10-03T02:00:00Z', 102.0, 'SUCCESS'),
('j304', 'cloud-bucket-B', '2023-10-04T02:00:00Z', 106.0, 'SUCCESS'), 

-- cold-glacier-A (Anomaly here!)
('j401', 'cold-glacier-A', '2023-10-01T04:00:00Z', 100.0, 'SUCCESS'),
('j402', 'cold-glacier-A', '2023-10-02T04:00:00Z', 105.0, 'SUCCESS'),
('j403', 'cold-glacier-A', '2023-10-03T04:00:00Z', 102.0, 'SUCCESS'),
('j404', 'cold-glacier-A', '2023-10-04T04:00:00Z', 300.0, 'SUCCESS'),

-- db-other (Anomaly, but not in downstream path)
('j501', 'san-local-3', '2023-10-01T00:00:00Z', 50.0, 'SUCCESS'),
('j502', 'san-local-3', '2023-10-02T00:00:00Z', 55.0, 'SUCCESS'),
('j503', 'san-local-3', '2023-10-03T00:00:00Z', 52.0, 'SUCCESS'),
('j504', 'san-local-3', '2023-10-04T00:00:00Z', 200.0, 'SUCCESS'); 
EOF

    chmod -R 777 /home/user
