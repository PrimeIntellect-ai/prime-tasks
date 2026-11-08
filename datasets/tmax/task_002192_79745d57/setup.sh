#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite DB
    sqlite3 backups.db <<EOF
CREATE TABLE backups (
    id TEXT PRIMARY KEY,
    parent_id TEXT,
    size_bytes INTEGER,
    backup_time DATETIME
);

INSERT INTO backups (id, parent_id, size_bytes, backup_time) VALUES 
('full_alpha', NULL, 50000, '2023-11-01 00:00:00'),
('inc_alpha_1', 'full_alpha', 1500, '2023-11-02 00:00:00'),
('inc_alpha_2', 'inc_alpha_1', 2000, '2023-11-03 00:00:00'),
('inc_alpha_3', 'inc_alpha_2', 1200, '2023-11-04 00:00:00'),
('inc_alpha_4', 'inc_alpha_3', 3000, '2023-11-05 00:00:00'),
('full_beta', NULL, 60000, '2023-11-01 00:00:00'),
('inc_beta_1', 'full_beta', 1000, '2023-11-02 00:00:00');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
