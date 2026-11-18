#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/scripts
mkdir -p /home/user/data

cat << 'EOF' > /home/user/scripts/build_report.py
import csv
import sys
import json

def build_report(csv_path):
    total_execution_time = 0.0
    query_count = 0

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # This will fail if there's a null byte (csv.Error)
            # or if ExecutionTime cannot be cast to float (ValueError)
            exec_time = float(row['ExecutionTime'])
            total_execution_time += exec_time
            query_count += 1

    report = {
        "total_queries": query_count,
        "total_execution_time": total_execution_time,
        "average_execution_time": total_execution_time / query_count if query_count else 0
    }

    print("Build successful:")
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python build_report.py <path_to_csv>")
        sys.exit(1)
    build_report(sys.argv[1])
EOF

cat << 'EOF' > /tmp/generate_csv.py
import os

os.makedirs("/home/user/scripts", exist_ok=True)
os.makedirs("/home/user/data", exist_ok=True)

with open("/home/user/data/query_logs.csv", "w", encoding="utf-8") as f:
    f.write("QueryID,Timestamp,UserID,QueryText,ExecutionTime\n")
    for i in range(1, 101):
        q_id = f"Q{i:04d}"
        timestamp = f"2023-10-24T10:{i%60:02d}:00"
        user = f"U{i%10}"
        query = "SELECT * FROM users"
        exec_time = f"{i * 0.1:.2f}"

        # Corrupt line 42 with a bad float
        if i == 42:
            exec_time = "NULL_VAL"

        # Corrupt line 76 with a null byte in the query text
        if i == 76:
            query = "SELECT * FROM users\x00 WHERE id=1"

        f.write(f"{q_id},{timestamp},{user},{query},{exec_time}\n")
EOF

python3 /tmp/generate_csv.py
rm /tmp/generate_csv.py

chmod -R 777 /home/user
