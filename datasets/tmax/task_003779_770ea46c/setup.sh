#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/process_logs.py
import sys
import json

def process(input_file, output_file):
    with open(input_file, 'r') as f_in, open(output_file, 'w') as f_out:
        for line_num, line in enumerate(f_in, 1):
            line = line.strip()
            if not line: continue

            parts = line.split(" - ")
            ip = parts[0]
            timestamp = parts[1].strip("[]")
            method = parts[2]
            path = parts[3]
            status = int(parts[4])

            record = {
                "ip": ip,
                "timestamp": timestamp,
                "method": method,
                "path": path,
                "status": status
            }
            f_out.write(json.dumps(record) + "\n")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: process_logs.py <input> <output>")
        sys.exit(1)
    process(sys.argv[1], sys.argv[2])
EOF

cat << 'EOF' > /home/user/generate_logs.py
import random
from datetime import datetime, timedelta

def generate_logs():
    methods = ["GET", "POST", "PUT", "DELETE"]
    paths = ["/home", "/api/v1/data", "/login", "/dashboard", "/api/v1/users"]
    statuses = [200, 201, 400, 401, 404, 500]

    start_time = datetime(2023, 10, 1, 0, 0, 0)

    with open("/home/user/access.log", "w") as f:
        for i in range(5000):
            if i == 3451:
                # Malformed line: missing the status code
                f.write("192.168.1.100 - [2023-10-12T10:00:00Z] - GET - /api/status\n")
            else:
                ip = f"10.0.{random.randint(0,255)}.{random.randint(1,254)}"
                dt = start_time + timedelta(minutes=i)
                timestamp = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
                method = random.choice(methods)
                path = random.choice(paths)
                status = random.choice(statuses)

                f.write(f"{ip} - [{timestamp}] - {method} - {path} - {status}\n")

generate_logs()
EOF

python3 /home/user/generate_logs.py
rm /home/user/generate_logs.py

chmod -R 777 /home/user
