#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/setup.py
import sqlite3
import json

# Create graph
graph = {
    "JOB_START": ["JOB_A", "JOB_B"],
    "JOB_A": ["JOB_C", "JOB_D"],
    "JOB_B": ["JOB_E"],
    "JOB_C": ["JOB_END"],
    "JOB_D": ["JOB_END"],
    "JOB_E": ["JOB_F"],
    "JOB_F": ["JOB_END"]
}
with open("/home/user/job_graph.json", "w") as f:
    json.dump(graph, f)

# Create DB
conn = sqlite3.connect("/home/user/backups.db")
c = conn.cursor()
c.execute("CREATE TABLE backup_logs (id INTEGER PRIMARY KEY, job_id TEXT, run_date TEXT, duration_seconds INTEGER)")
c.execute("CREATE TABLE job_configs (job_id TEXT PRIMARY KEY, config_json TEXT)")

logs = [
    ("JOB_START", "2023-10-01", 100), ("JOB_START", "2023-10-02", 110), ("JOB_START", "2023-10-03", 120),
    ("JOB_A", "2023-10-01", 50), ("JOB_A", "2023-10-02", 60), ("JOB_A", "2023-10-03", 70), ("JOB_A", "2023-10-04", 80),
    ("JOB_C", "2023-10-01", 300), ("JOB_C", "2023-10-02", 300), ("JOB_C", "2023-10-03", 300),
    ("JOB_END", "2023-10-01", 10), ("JOB_END", "2023-10-02", 20),
]

for job, date, dur in logs:
    c.execute("INSERT INTO backup_logs (job_id, run_date, duration_seconds) VALUES (?, ?, ?)", (job, date, dur))

configs = [
    ("JOB_START", '{"storage_target": "s3", "retention": 30}'),
    ("JOB_A", '{"storage_target": "gcs", "retention": 14}'),
    ("JOB_B", '{"storage_target": "azure", "retention": 7}'),
    ("JOB_C", '{"storage_target": "s3", "retention": 30}'),
    ("JOB_END", '{"storage_target": "local", "retention": 1}')
]

for job, conf in configs:
    c.execute("INSERT INTO job_configs (job_id, config_json) VALUES (?, ?)", (job, conf))

conn.commit()
conn.close()
EOF

python3 /home/user/setup.py
rm /home/user/setup.py

chmod -R 777 /home/user
