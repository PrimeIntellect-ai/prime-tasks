#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    mkdir -p /home/user

    # Create the SQLite database and populate it
    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE backup_jobs (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER,
    job_name TEXT,
    bytes_transferred INTEGER,
    status TEXT
);

INSERT INTO backup_jobs (id, parent_id, job_name, bytes_transferred, status) VALUES 
(1, NULL, 'full_db_1', 10000, 'success'),
(2, 1, 'inc_db_1_1', 500, 'success'),
(3, 2, 'inc_db_1_2', 250, 'success'),
(4, NULL, 'full_db_2', 20000, 'success'),
(5, 4, 'inc_db_2_1', 1000, 'success'),
(6, NULL, 'full_db_3', 5000, 'success'),
(7, 6, 'inc_db_3_1', 100, 'success'),
(8, 7, 'inc_db_3_2', 150, 'success'),
(9, 8, 'inc_db_3_3', 50, 'success');
EOF

    # Create the query.sql file
    cat << 'EOF' > /home/user/query.sql
WITH RECURSIVE backup_chain AS (
    SELECT id, id as root_id, bytes_transferred
    FROM backup_jobs
    WHERE parent_id IS NULL

    UNION ALL

    SELECT b.id, c.root_id, b.bytes_transferred
    FROM backup_jobs b
    JOIN backup_chain c ON b.parent_id = c.id
)
SELECT root_id, SUM(bytes_transferred) as total_bytes
FROM backup_chain
GROUP BY root_id
ORDER BY root_id;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
