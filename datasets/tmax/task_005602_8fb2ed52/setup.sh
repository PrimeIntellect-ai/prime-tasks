#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/legacy_etl.db')
c = conn.cursor()

c.execute('''CREATE TABLE etl_jobs (job_id INTEGER PRIMARY KEY, job_name TEXT)''')
c.execute('''CREATE TABLE job_deps (upstream_id INTEGER, downstream_id INTEGER)''')

jobs = [
    (1, "Extract_Sales_DB"),
    (2, "Extract_Marketing_API"),
    (3, "Clean_Sales_Data"),
    (4, "Clean_Marketing_Data"),
    (5, "Join_Sales_Marketing"),
    (6, "Calculate_Metrics"),
    (7, "Load_Fact_Sales"),
    (8, "Send_Email_Report"),
    (9, "Unrelated_Job")
]

deps = [
    (1, 3), # Extract_Sales -> Clean_Sales
    (2, 4), # Extract_Mktg -> Clean_Mktg
    (3, 5), # Clean_Sales -> Join
    (4, 5), # Clean_Mktg -> Join
    (5, 6), # Join -> Calc
    (6, 7), # Calc -> Load
    (7, 8)  # Load -> Email
]

c.executemany("INSERT INTO etl_jobs VALUES (?, ?)", jobs)
c.executemany("INSERT INTO job_deps VALUES (?, ?)", deps)

conn.commit()
conn.close()
EOF

    python3 /home/user/setup_db.py
    rm /home/user/setup_db.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
