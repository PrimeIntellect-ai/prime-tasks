#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create the SQLite database
    sqlite3 backup_metadata.db <<EOF
CREATE TABLE servers (
    id INTEGER PRIMARY KEY,
    hostname TEXT NOT NULL,
    parent_id INTEGER,
    FOREIGN KEY(parent_id) REFERENCES servers(id)
);

CREATE TABLE backups (
    id INTEGER PRIMARY KEY,
    server_id INTEGER NOT NULL,
    timestamp DATETIME NOT NULL,
    size_mb INTEGER NOT NULL,
    status TEXT NOT NULL,
    FOREIGN KEY(server_id) REFERENCES servers(id)
);

INSERT INTO servers (id, hostname, parent_id) VALUES
(1, 'db-main', NULL),
(2, 'db-replica1', 1),
(3, 'db-replica2', 1),
(4, 'cache-master', NULL),
(5, 'cache-node1', 4);

INSERT INTO backups (id, server_id, timestamp, size_mb, status) VALUES
(1, 1, '2023-10-01 10:00:00', 1050, 'SUCCESS'),
(2, 1, '2023-10-02 10:00:00', 1060, 'SUCCESS'),
(3, 1, '2023-10-03 10:00:00', 100, 'FAILED'),
(4, 2, '2023-10-01 10:05:00', 950, 'SUCCESS'),
(5, 2, '2023-10-02 10:05:00', 955, 'SUCCESS'),
(6, 3, '2023-10-01 10:10:00', 960, 'SUCCESS'),
(7, 4, '2023-10-01 11:00:00', 200, 'SUCCESS'),
(8, 4, '2023-10-02 11:00:00', 210, 'SUCCESS'),
(9, 5, '2023-10-02 11:05:00', 190, 'SUCCESS'),
(10, 5, '2023-10-03 11:05:00', 0, 'FAILED');
EOF

    # Create the broken script
    cat << 'EOF' > /home/user/generate_report.sh
#!/bin/bash
sqlite3 /home/user/backup_metadata.db -csv "SELECT s.hostname, b.size_mb FROM servers s, backups b WHERE b.status = 'SUCCESS';" > /home/user/bad_report.csv
EOF

    chmod +x /home/user/generate_report.sh

    chmod -R 777 /home/user
