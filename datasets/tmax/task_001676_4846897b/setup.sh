#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE backup_jobs (
    id INTEGER PRIMARY KEY,
    name TEXT,
    suite_id INTEGER,
    size_bytes INTEGER
);

CREATE TABLE job_dependencies (
    job_id INTEGER,
    parent_job_id INTEGER
);

INSERT INTO backup_jobs VALUES
(1, 'full_cluster_backup', 100, 5000),
(2, 'db_primary', 100, 2000),
(3, 'db_replica', 100, 2000),
(4, 'app_logs', 101, 8000),
(5, 'user_uploads', 101, 15000),
(6, 'cache_dump', 102, 1000),
(7, 'unrelated_job', 100, 99999);

INSERT INTO job_dependencies VALUES
(2, 1),
(3, 1),
(4, 2),
(5, 2),
(6, 3);
EOF

    chmod -R 777 /home/user
