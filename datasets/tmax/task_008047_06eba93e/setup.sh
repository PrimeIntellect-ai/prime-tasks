#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/container_logs.txt
[2023-10-01T00:00:00Z] OK 100.0
[2023-10-01T01:15:00Z] FAIL 300.1
[2023-10-01T02:30:00Z] OK 150.2
[2023-10-01T03:45:00Z]   FAIL 100.2
[2023-10-01T05:00:00Z] OK 200.0
[2023-10-01T06:15:00Z] FAIL   50.15
EOF

    cat << 'EOF' > /home/user/uptime_monitor.py
import sys

def parse_logs(filepath):
    total_downtime = 0.0
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            # Format: [TIMESTAMP] STATUS DURATION_MS
            parts = line.split(" ")
            status = parts[1]
            duration = float(parts[2])

            if status == "FAIL":
                total_downtime += duration
    return total_downtime

def calculate_sla(downtime_ms):
    # 24 hours in ms
    total_time = 86400000.0
    uptime = 100.0 - (downtime_ms / total_time * 100.0)
    return uptime

if __name__ == "__main__":
    dt = parse_logs("/home/user/container_logs.txt")
    sla = calculate_sla(dt)
    print(f"Daily SLA: {sla}%")
EOF

    chmod +x /home/user/uptime_monitor.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
