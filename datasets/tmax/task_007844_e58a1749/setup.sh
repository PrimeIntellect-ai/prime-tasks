#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    # Create setup_db.py to initialize the SQLite database
    cat << 'EOF' > setup_db.py
import sqlite3

conn = sqlite3.connect('pipeline.db')
c = conn.cursor()

c.execute("CREATE TABLE jobs (job_id TEXT PRIMARY KEY, exec_time_sec INTEGER)")
c.execute("CREATE TABLE dependencies (parent_id TEXT, child_id TEXT)")

jobs_data = [
    ('ingest', 10),
    ('clean', 25),
    ('transform', 40),
    ('metrics', 5),
    ('aggregate', 15),
    ('report', 5)
]

deps_data = [
    ('ingest', 'clean'),
    ('clean', 'transform'),
    ('clean', 'metrics'),
    ('transform', 'aggregate'),
    ('aggregate', 'report')
]

c.executemany("INSERT INTO jobs VALUES (?, ?)", jobs_data)
c.executemany("INSERT INTO dependencies VALUES (?, ?)", deps_data)

conn.commit()
conn.close()
EOF

    python3 setup_db.py
    rm setup_db.py

    # Create the flawed analyze.py script
    cat << 'EOF' > analyze.py
import sqlite3
import csv

def run_analysis():
    conn = sqlite3.connect('pipeline.db')
    cursor = conn.cursor()

    # Flawed query with implicit cross join and no proper graph traversal
    bad_sql = """
    SELECT j1.job_id, 0 as step, j1.exec_time_sec, 
           SUM(j2.exec_time_sec) OVER (ORDER BY j1.job_id) as cumulative_time
    FROM jobs j1, jobs j2
    WHERE j1.job_id IN ('ingest', 'clean', 'transform', 'aggregate', 'report')
    """

    cursor.execute(bad_sql)
    results = cursor.fetchall()

    with open('pipeline_report.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['job_id', 'step', 'exec_time_sec', 'cumulative_time'])
        writer.writerows(results)

if __name__ == "__main__":
    run_analysis()
EOF

    chmod -R 777 /home/user
