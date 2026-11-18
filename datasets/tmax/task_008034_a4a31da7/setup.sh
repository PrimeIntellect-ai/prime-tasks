#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT, datacenter TEXT);
CREATE TABLE backup_jobs (job_id INTEGER PRIMARY KEY, server_id INTEGER, status TEXT, timestamp DATETIME);

INSERT INTO servers (id, hostname, datacenter) VALUES (1, 'db-prod-01', 'us-east-1');
INSERT INTO servers (id, hostname, datacenter) VALUES (2, 'db-prod-02', 'us-east-1');
INSERT INTO servers (id, hostname, datacenter) VALUES (3, 'cache-01', 'us-west-2');
INSERT INTO servers (id, hostname, datacenter) VALUES (4, 'app-01', 'us-east-1');

INSERT INTO backup_jobs (job_id, server_id, status, timestamp) VALUES (101, 1, 'SUCCESS', '2023-10-01 10:00:00');
INSERT INTO backup_jobs (job_id, server_id, status, timestamp) VALUES (102, 1, 'FAILED', '2023-10-02 10:00:00');
INSERT INTO backup_jobs (job_id, server_id, status, timestamp) VALUES (103, 1, 'FAILED', '2023-10-03 10:00:00');

INSERT INTO backup_jobs (job_id, server_id, status, timestamp) VALUES (104, 2, 'SUCCESS', '2023-10-01 10:00:00');

INSERT INTO backup_jobs (job_id, server_id, status, timestamp) VALUES (105, 3, 'FAILED', '2023-10-01 10:00:00');

INSERT INTO backup_jobs (job_id, server_id, status, timestamp) VALUES (106, 4, 'FAILED', '2023-10-01 10:00:00');
EOF

    cat <<EOF > /home/user/nosql_metrics.jsonl
{"hostname": "db-prod-01", "type": "backup", "bytes_transferred": 1000, "duration_seconds": 10}
{"hostname": "db-prod-01", "type": "backup", "bytes_transferred": 2000, "duration_seconds": 15}
{"hostname": "db-prod-01", "type": "restore", "bytes_transferred": 5000, "duration_seconds": 5}
{"hostname": "db-prod-02", "type": "backup", "bytes_transferred": 10000, "duration_seconds": 20}
{"hostname": "app-01", "type": "backup", "bytes_transferred": 500, "duration_seconds": 2}
{"hostname": "cache-01", "type": "backup", "bytes_transferred": 8000, "duration_seconds": 8}
EOF

    chmod -R 777 /home/user
