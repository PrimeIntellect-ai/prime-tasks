#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

db_path = "/home/user/backups.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('''CREATE TABLE job_dependencies (
                source_job TEXT,
                target_job TEXT,
                is_active INTEGER
             )''')

# Active edges
edges = [
    ("job_A", "job_B", 1),
    ("job_B", "job_C", 1),
    ("job_A", "job_C", 1),
    ("job_C", "job_D", 1),
    ("job_E", "job_D", 1),
    ("job_E", "job_F", 1),
    ("job_F", "job_C", 1),
    # Inactive/stale edges
    ("job_D", "job_A", 0),
    ("job_F", "job_A", 0),
    ("job_B", "job_E", 0)
]

c.executemany("INSERT INTO job_dependencies VALUES (?, ?, ?)", edges)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
