#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/log_pipeline/data
    mkdir -p /home/user/log_pipeline/output

    cat << 'EOF' > /home/user/log_pipeline/requirements.txt
requests==2.20.0
urllib3>=1.25.0
EOF

    cat << 'EOF' > /home/user/log_pipeline/data/raw_logs.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "ip": "10.0.0.1", "level": "ERROR", "message": "Connection timeout"}
{"timestamp": "2023-10-01T10:01:00Z", "ip": "10.0.0.2", "level": "INFO", "message": "Job started"}
{"timestamp": "2023-10-01T10:02:00Z", "ip": "10.0.0.1", "level": "ERROR", "message": "Disk full"}
{"timestamp": "2023-10-01T10:03:00Z", "ip": "10.0.0.
{"timestamp": "2023-10-01T10:04:00Z", "ip": "10.0.0.3", "level": "ERROR", "message": "OOM Killed"}
{"timestamp": "2023-10-01T10:05:00Z", "ip": "10.0.0.1", "level": "INFO", "message": "Cleanup done"}
{bad_json_here: true}
{"timestamp": "2023-10-01T10:07:00Z", "ip": "10.0.0.2", "level": "ERROR", "message": "CPU pegged"}
EOF

    python3 -c '
import sqlite3
conn = sqlite3.connect("/home/user/log_pipeline/data/metadata.db")
c = conn.cursor()
c.execute("CREATE TABLE regions (id INTEGER PRIMARY KEY, name TEXT)")
c.execute("CREATE TABLE servers (ip TEXT PRIMARY KEY, region_id INTEGER)")
c.executemany("INSERT INTO regions (id, name) VALUES (?, ?)", [(1, "us-east-1"), (2, "us-west-2"), (3, "eu-central-1")])
c.executemany("INSERT INTO servers (ip, region_id) VALUES (?, ?)", [("10.0.0.1", 1), ("10.0.0.2", 2), ("10.0.0.3", 1)])
conn.commit()
conn.close()
'

    cat << 'EOF' > /home/user/log_pipeline/process_logs.py
import json
import sqlite3
import os

DB_PATH = "/home/user/log_pipeline/data/metadata.db"
LOG_PATH = "/home/user/log_pipeline/data/raw_logs.jsonl"
OUT_PATH = "/home/user/log_pipeline/output/summary.json"

def get_server_regions():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    # BUG: Missing JOIN condition (Cartesian product)
    c.execute("SELECT servers.ip, regions.name FROM servers, regions")

    mapping = {}
    for ip, region in c.fetchall():
        mapping[ip] = region
    conn.close()
    return mapping

def process_logs():
    region_mapping = get_server_regions()
    error_counts = {}

    with open(LOG_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            # BUG: No error handling for bad JSON
            record = json.loads(line.strip())

            if record.get("level") == "ERROR":
                ip = record.get("ip")
                region = region_mapping.get(ip, "unknown")
                error_counts[region] = error_counts.get(region, 0) + 1

    with open(OUT_PATH, 'w', encoding='utf-8') as f:
        json.dump(error_counts, f, indent=4)

if __name__ == "__main__":
    process_logs()
EOF

    chmod +x /home/user/log_pipeline/process_logs.py
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
