#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/log_pipeline

cat << 'EOF' > /home/user/log_pipeline/process_logs.py
import json
import sys

def parse_brackets(text):
    result = []
    while '[' in text:
        start = text.find('[')
        end = text.find(']')
        if start != -1 and end != -1 and start < end:
            if start > 0:
                result.append(text[:start].strip())
            text = text[start+1:end] + " " + text[end+1:]
        elif start != -1 and end == -1:
            # BUG: Infinite loop if closing bracket is missing
            continue
        elif end != -1 and start == -1:
            text = text[:end] + text[end+1:]
        elif end < start:
            text = text[:end] + text[end+1:]
    if text.strip():
        result.append(text.strip())
    return result

def parse_line(line):
    parts = line.strip().split(' ', 3)
    if len(parts) < 4: return None
    timestamp, ip, status, rest = parts
    modules = parse_brackets(rest)
    return {
        "timestamp": timestamp,
        "ip": ip,
        "status": status,
        "modules": modules
    }

def main():
    if len(sys.argv) < 2:
        print("Usage: python process_logs.py <logfile>")
        sys.exit(1)

    parsed = []
    with open(sys.argv[1], 'r') as f:
        for line in f:
            res = parse_line(line)
            if res:
                parsed.append(res)

    with open('/home/user/log_pipeline/parsed_logs.json', 'w') as f:
        json.dump(parsed, f, indent=2)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > /home/user/log_pipeline/generate_logs.py
import random
from datetime import datetime, timedelta

start_time = datetime(2023, 10, 12, 10, 0, 0)
ips = [f"192.168.1.{i}" for i in range(10, 20)]

random.seed(42)

with open('/home/user/log_pipeline/logs.txt', 'w') as f:
    for i in range(1, 5001):
        dt = start_time + timedelta(seconds=i)
        ip = random.choice(ips)
        status = random.choice(["200", "200", "200", "404", "500"])

        # Inject anomaly
        if datetime(2023, 10, 12, 10, 15, 0) <= dt <= datetime(2023, 10, 12, 10, 19, 59):
            if random.random() < 0.2:
                ip = "10.0.0.99"
                status = "500"

        msg = "[auth] User login successful" if status == "200" else "[db] Connection timeout"

        # Inject hang bug
        if i == 3142:
            msg = "[auth User login failed"  # missing closing bracket

        f.write(f"{dt.strftime('%Y-%m-%dT%H:%M:%SZ')} {ip} {status} {msg}\n")
EOF

python3 /home/user/log_pipeline/generate_logs.py
rm /home/user/log_pipeline/generate_logs.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
