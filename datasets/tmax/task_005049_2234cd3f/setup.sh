#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/uptime_monitor
cd /home/user/uptime_monitor

cat << 'EOF' > health_logs.txt
2023-10-12T10:00:01Z user-service 200 45
2023-10-12T10:00:02Z user-service 200 42
2023-10-12T10:00:03Z user-service 200 39
2023-10-12T10:00:04Z user-service 400 12
2023-10-12T10:00:05Z user-service 200 44
2023-10-12T10:00:06Z user-service 404 15
2023-10-12T10:00:07Z user-service 500 120
2023-10-12T10:00:08Z user-service 200 40
2023-10-12T10:00:09Z user-service 200 41
2023-10-12T10:00:10Z user-service 200 38
2023-10-12T10:00:11Z user-service TIMEOUT -
2023-10-12T10:00:12Z user-service 200 45
2023-10-12T10:00:13Z user-service 200 42
2023-10-12T10:00:14Z user-service 400 11
2023-10-12T10:00:15Z user-service 200 44
2023-10-12T10:00:16Z user-service 404 14
2023-10-12T10:00:17Z user-service 500 130
2023-10-12T10:00:18Z user-service 200 40
2023-10-12T10:00:19Z user-service 200 41
2023-10-12T10:00:20Z user-service 200 38
2023-10-12T10:00:21Z user-service TIMEOUT -
2023-10-12T10:00:22Z user-service 200 45
2023-10-12T10:00:23Z user-service 200 42
2023-10-12T10:00:24Z user-service 400 13
2023-10-12T10:00:25Z user-service 200 44
2023-10-12T10:00:26Z user-service 404 15
2023-10-12T10:00:27Z user-service 500 125
2023-10-12T10:00:28Z user-service 200 40
2023-10-12T10:00:29Z user-service 200 41
2023-10-12T10:00:30Z user-service 200 38
EOF

# Append remaining 200s to make exactly 100 lines using seq instead of brace expansion
for i in $(seq 31 100); do
  echo "2023-10-12T10:00:${i}Z user-service 200 40" >> health_logs.txt
done

cat << 'EOF' > calculator.py
import sys
import json

def process_logs(filepath):
    total_requests = 0
    error_requests = 0

    with open(filepath, 'r') as f:
        for line in f:
            if not line.strip(): continue
            parts = line.strip().split()

            # BUG 1: Will throw ValueError on 'TIMEOUT'
            status = int(parts[2])

            total_requests += 1

            # BUG 2: Counts 4xx as errors
            if status >= 400:
                error_requests += 1

    if total_requests == 0:
        return {}

    error_rate = error_requests / total_requests
    uptime_pct = (1 - error_rate) * 100

    # BUG 3: Incorrect formula for burn rate. Divides by 0.999 instead of 0.001
    burn_rate = error_rate / 0.999

    return {
        "total_requests": total_requests,
        "error_requests": error_requests,
        "uptime_percentage": round(uptime_pct, 4),
        "burn_rate": round(burn_rate, 4)
    }

if __name__ == "__main__":
    metrics = process_logs("health_logs.txt")
    with open("final_metrics.json", "w") as f:
        json.dump(metrics, f, indent=4)
EOF

chmod -R 777 /home/user
