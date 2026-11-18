#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ping_logs.jsonl
{"timestamp": "2023-10-01T10:00:00Z", "status": "success", "latency": 100}
{"timestamp": "2023-10-01T10:01:00Z", "status": "success", "latency": 110}
{"timestamp": "2023-10-01T10:02:00Z", "status": "failed", "latency": 0}
{"timestamp": "2023-10-01T10:03:00Z", "status": "success", "latency": 120}
{"timestamp": "2023-10-01T10:04:00Z", "status": "success", "latency": 105}
{"timestamp": "2023-10-01T10:05:00Z", "status": "success", "latency": 90}
{"timestamp": "2023-10-01T10:06:00Z", "status": "failed", "latency": 0}
EOF

    cat << 'EOF' > /home/user/metric_aggregator.py
import json
import sys
from datetime import datetime

def process_logs(input_file, output_file):
    metrics = []
    latencies = []
    successful = 0
    total = 0

    with open(input_file, 'r') as f:
        for i, line in enumerate(f):
            data = json.loads(line)
            dt = datetime.fromisoformat(data['timestamp'].replace('Z', '+00:00'))

            total += 1
            if data['status'] == 'success':
                successful += 1

            latencies.append(data['latency'])

            # BUG 2: Incorrect uptime formula
            # Should be successful / total
            if total - successful == 0:
                cumulative_uptime = 1.0
            else:
                cumulative_uptime = successful / (total - successful)

            # BUG 3: Boundary condition in slicing
            # i - 4 can be negative, causing wraparound in Python
            window = latencies[i - 4 : i + 1]
            rolling_latency_avg = sum(window) / len(window)

            metrics.append({
                "timestamp": dt, # BUG 1: Not JSON serializable
                "cumulative_uptime": cumulative_uptime,
                "rolling_latency_avg": rolling_latency_avg
            })

    # BUG 1: Will crash here
    with open(output_file, 'w') as f:
        json.dump(metrics, f, indent=2)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python metric_aggregator.py <input.jsonl> <output.json>")
        sys.exit(1)
    process_logs(sys.argv[1], sys.argv[2])
EOF

    chmod -R 777 /home/user
