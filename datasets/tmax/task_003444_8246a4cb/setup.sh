#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/backups.db <<EOF
CREATE TABLE backups (
    id INTEGER PRIMARY KEY,
    job_name TEXT,
    size INTEGER,
    created_at DATETIME
);

CREATE TABLE backup_deps (
    backup_id INTEGER,
    depends_on INTEGER,
    FOREIGN KEY(backup_id) REFERENCES backups(id),
    FOREIGN KEY(depends_on) REFERENCES backups(id)
);

INSERT INTO backups (id, job_name, size, created_at) VALUES
(1, 'DB_PROD_FULL', 1000, '2023-01-01 00:00:00'),
(2, 'DB_PROD_INC_1', 100, '2023-01-02 00:00:00'),
(3, 'DB_PROD_INC_2', 150, '2023-01-03 00:00:00'),
(4, 'DB_PROD_INC_3', 120, '2023-01-04 00:00:00'),
(5, 'OTHER_BACKUP_FULL', 500, '2023-01-01 12:00:00'),
(6, 'OTHER_BACKUP_INC', 50, '2023-01-02 12:00:00');

INSERT INTO backup_deps (backup_id, depends_on) VALUES
(2, 1),
(3, 2),
(4, 3),
(6, 5);
EOF

    cat << 'EOF' > /home/user/buggy_export.py
import sqlite3
import json

conn = sqlite3.connect('/home/user/backups.db')
cursor = conn.cursor()

query = """
WITH RECURSIVE backup_chain AS (
    SELECT id, job_name, size, created_at
    FROM backups
    WHERE job_name = 'DB_PROD_FULL'

    UNION ALL

    SELECT b.id, b.job_name, b.size, b.created_at
    FROM backups b, backup_chain bc, backup_deps bd
    -- BUG: Implicit cross join, missing join conditions
)
SELECT id, job_name, size, 
       SUM(size) OVER (ORDER BY created_at) as running_total
FROM backup_chain
"""

# The query will hang or return massive results due to the cross join, 
# so the execution is commented out for safety in the buggy version.
# results = cursor.execute(query).fetchall()
# columns = [col[0] for col in cursor.description]
# data = [dict(zip(columns, row)) for row in results]
# with open('/home/user/fixed_metrics.json', 'w') as f:
#     json.dump(data, f, indent=2)
EOF
    chmod +x /home/user/buggy_export.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
