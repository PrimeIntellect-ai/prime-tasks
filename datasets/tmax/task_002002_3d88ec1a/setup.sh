#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE backups (
    id TEXT PRIMARY KEY,
    node_id INTEGER,
    timestamp INTEGER,
    size_bytes INTEGER
);

CREATE TABLE network (
    source_node INTEGER,
    dest_node INTEGER,
    transfer_cost INTEGER
);

-- Insert backup data
INSERT INTO backups (id, node_id, timestamp, size_bytes) VALUES
('b1', 1, 1600000000, 100),
('b2', 1, 1600000100, 150),
('b3', 2, 1600000050, 200),
('b4', 3, 1600000000, 300),
('b5', 3, 1600000200, 350),
('b6', 4, 1600000300, 400),
('b7', 5, 1600000000, 500);

-- Insert network topology
-- 0 is the archive node
INSERT INTO network (source_node, dest_node, transfer_cost) VALUES
(1, 0, 10),
(2, 1, 5),
(2, 3, 2),
(3, 0, 15),
(4, 3, 5),
(4, 2, 1),
(5, 6, 10);
EOF

    sqlite3 /home/user/backup_network.db < /tmp/setup_db.sql
    chown user:user /home/user/backup_network.db

    chmod -R 777 /home/user
