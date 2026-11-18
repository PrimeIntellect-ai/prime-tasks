#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 golang gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

# Initialize the sqlite database
sqlite3 /home/user/backups.db <<EOF
CREATE TABLE target_dbs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    cluster_name TEXT NOT NULL
);

CREATE TABLE backup_jobs (
    job_id INTEGER PRIMARY KEY AUTOINCREMENT,
    db_id INTEGER NOT NULL,
    run_time DATETIME NOT NULL,
    status TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    FOREIGN KEY(db_id) REFERENCES target_dbs(id)
);

INSERT INTO target_dbs (id, name, cluster_name) VALUES 
(1, 'auth_db', 'eu-central-1'),
(2, 'payments_db', 'eu-central-1'),
(3, 'users_db', 'us-east-1');

INSERT INTO backup_jobs (db_id, run_time, status, size_bytes) VALUES
(1, '2023-10-01 10:00:00', 'SUCCESS', 1000),
(1, '2023-10-02 10:00:00', 'FAILED', 100),
(1, '2023-10-03 10:00:00', 'SUCCESS', 1050),
(1, '2023-10-04 10:00:00', 'SUCCESS', 1100),
(2, '2023-10-01 11:00:00', 'SUCCESS', 5000),
(2, '2023-10-02 11:00:00', 'SUCCESS', 4800),
(3, '2023-10-01 12:00:00', 'SUCCESS', 2000);
EOF

# Install go-sqlite3 bindings for the agent
cd /home/user
go mod init backup_analysis
go get github.com/mattn/go-sqlite3

chmod -R 777 /home/user
