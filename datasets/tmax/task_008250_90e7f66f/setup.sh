#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install system packages needed for the task
    apt-get install -y sqlite3 libsqlite3-dev build-essential

    # Create the user
    useradd -m -s /bin/bash user || true

    # Setup the database
    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE clusters (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE backups (id INTEGER PRIMARY KEY, cluster_id INTEGER, timestamp INTEGER, duration_sec INTEGER, status TEXT);

-- Cluster 1: Most recent is FAILED
INSERT INTO clusters VALUES (1, 'us-east-db1');
INSERT INTO backups VALUES (1, 1, 1000, 300, 'SUCCESS');
INSERT INTO backups VALUES (2, 1, 2000, 310, 'SUCCESS');
INSERT INTO backups VALUES (3, 1, 3000, 150, 'FAILED');

-- Cluster 2: Healthy, no failures, duration stable
INSERT INTO clusters VALUES (2, 'us-west-db1');
INSERT INTO backups VALUES (4, 2, 1000, 100, 'SUCCESS');
INSERT INTO backups VALUES (5, 2, 2000, 105, 'SUCCESS');
INSERT INTO backups VALUES (6, 2, 3000, 95, 'SUCCESS');
INSERT INTO backups VALUES (7, 2, 4000, 100, 'SUCCESS');

-- Cluster 3: Duration spike (> 1.5 * avg of previous 3)
INSERT INTO clusters VALUES (3, 'eu-central-db1');
INSERT INTO backups VALUES (8,  3, 1000, 200, 'SUCCESS');
INSERT INTO backups VALUES (9,  3, 2000, 210, 'SUCCESS');
INSERT INTO backups VALUES (10, 3, 3000, 190, 'SUCCESS');
INSERT INTO backups VALUES (11, 3, 4000, 350, 'SUCCESS');

-- Cluster 4: Insufficient data for duration spike, most recent is SUCCESS
INSERT INTO clusters VALUES (4, 'ap-south-db1');
INSERT INTO backups VALUES (12, 4, 1000, 100, 'SUCCESS');
INSERT INTO backups VALUES (13, 4, 2000, 500, 'SUCCESS');

-- Cluster 5: Duration spike but interrupted by FAILED, still evaluate recent SUCCESS against prev 3 SUCCESS
INSERT INTO clusters VALUES (5, 'sa-east-db1');
INSERT INTO backups VALUES (14, 5, 1000, 100, 'SUCCESS');
INSERT INTO backups VALUES (15, 5, 2000, 100, 'SUCCESS');
INSERT INTO backups VALUES (16, 5, 3000, 100, 'SUCCESS');
INSERT INTO backups VALUES (17, 5, 4000, 999, 'FAILED');
INSERT INTO backups VALUES (18, 5, 5000, 160, 'SUCCESS');
EOF

    sqlite3 /home/user/backup_metadata.db < /tmp/setup_db.sql
    rm /tmp/setup_db.sql

    # Ensure correct permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
