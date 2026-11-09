#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    # Create SQLite Database
    sqlite3 backups.db <<EOF
CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT);
CREATE TABLE backup_jobs (id TEXT PRIMARY KEY, server_id INTEGER, type TEXT, status TEXT, size_mb INTEGER);
CREATE TABLE backup_lineage (child_id TEXT, parent_id TEXT);

INSERT INTO servers VALUES (1, 'db-prod-01');
INSERT INTO servers VALUES (2, 'db-prod-02');
INSERT INTO servers VALUES (3, 'db-staging-01');

INSERT INTO backup_jobs VALUES ('full_100', 1, 'FULL', 'SUCCESS', 5000);
INSERT INTO backup_jobs VALUES ('diff_150', 1, 'DIFF', 'SUCCESS', 500);
INSERT INTO backup_jobs VALUES ('incr_999', 1, 'INCR', 'SUCCESS', 50);

INSERT INTO backup_jobs VALUES ('full_200', 2, 'FULL', 'SUCCESS', 8000);
INSERT INTO backup_jobs VALUES ('incr_201', 2, 'INCR', 'FAILED', 0);

INSERT INTO backup_jobs VALUES ('full_300', 3, 'FULL', 'SUCCESS', 2000);

INSERT INTO backup_lineage VALUES ('incr_999', 'diff_150');
INSERT INTO backup_lineage VALUES ('diff_150', 'full_100');
INSERT INTO backup_lineage VALUES ('incr_201', 'full_200');
EOF

    # Create the buggy script
    cat << 'EOF' > /home/user/sql_report.sh
#!/bin/bash
sqlite3 -header -csv /home/user/backups.db "
SELECT s.hostname, SUM(b.size_mb) as total_size_mb
FROM servers s, backup_jobs b
WHERE b.status = 'SUCCESS'
GROUP BY s.hostname
ORDER BY total_size_mb DESC;
" > /home/user/fixed_sql_report.csv
EOF
    chmod +x /home/user/sql_report.sh

    # Create the JSON file
    cat << 'EOF' > /home/user/nosql_backups.json
[
  {"cluster_id": "mongo-main", "job_id": "m1", "status": "SUCCESS", "timestamp": 1630000000, "size_gb": 100},
  {"cluster_id": "mongo-main", "job_id": "m2", "status": "FAILED", "timestamp": 1630003600, "size_gb": 0},
  {"cluster_id": "mongo-main", "job_id": "m3", "status": "SUCCESS", "timestamp": 1630086400, "size_gb": 105},
  {"cluster_id": "cassandra-logs", "job_id": "c1", "status": "SUCCESS", "timestamp": 1630000000, "size_gb": 500},
  {"cluster_id": "cassandra-logs", "job_id": "c2", "status": "SUCCESS", "timestamp": 1629000000, "size_gb": 480}
]
EOF

    chmod -R 777 /home/user
