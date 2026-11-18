#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg sqlite3
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak -w /app/incident_report.wav "When writing the reconciliation query, ensure that you completely exclude any storage nodes located in the 'us-east-legacy' region. Also, a backup job is only considered successful if its status is exactly 'COMPLETED' and the integrity_hash is not null."

    # Create sample database
    python3 -c "
import sqlite3
conn = sqlite3.connect('/app/sample_backup_meta.db')
c = conn.cursor()
c.execute('CREATE TABLE storage_nodes(node_id INTEGER PRIMARY KEY, node_name TEXT, region TEXT)')
c.execute('CREATE TABLE backup_jobs(job_id INTEGER PRIMARY KEY, node_id INTEGER, status TEXT, integrity_hash TEXT, completed_at TEXT)')
c.execute('CREATE TABLE job_chunks(chunk_id INTEGER PRIMARY KEY, job_id INTEGER, bytes_size INTEGER)')
conn.commit()
conn.close()
"

    # Create oracle script
    cat << 'EOF' > /app/oracle_reconcile.py
import sys
import sqlite3
import csv

def main():
    db_path = sys.argv[1]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    query = """
    WITH ValidJobs AS (
        SELECT bj.job_id, bj.node_id, bj.completed_at
        FROM backup_jobs bj
        JOIN storage_nodes sn ON bj.node_id = sn.node_id
        WHERE bj.status = 'COMPLETED' 
          AND bj.integrity_hash IS NOT NULL
          AND sn.region != 'us-east-legacy'
    ),
    LatestJobs AS (
        SELECT job_id, node_id
        FROM (
            SELECT job_id, node_id, 
                   ROW_NUMBER() OVER(PARTITION BY node_id ORDER BY completed_at DESC) as rn
            FROM ValidJobs
        ) WHERE rn = 1
    ),
    JobSizes AS (
        SELECT job_id, SUM(bytes_size) as total_backup_bytes
        FROM job_chunks
        GROUP BY job_id
    )
    SELECT sn.node_id, sn.node_name, lj.job_id, COALESCE(js.total_backup_bytes, 0)
    FROM storage_nodes sn
    JOIN LatestJobs lj ON sn.node_id = lj.node_id
    LEFT JOIN JobSizes js ON lj.job_id = js.job_id
    ORDER BY sn.node_id ASC;
    """
    cur.execute(query)
    writer = csv.writer(sys.stdout)
    for row in cur.fetchall():
        writer.writerow(row)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_reconcile.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
