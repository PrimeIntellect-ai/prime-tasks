#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/health_aggregator.py
import json
import sys

def compute_score(metrics):
    base = metrics.get('base_score', 100)
    penalty = metrics.get('penalty', 0)
    latency = metrics.get('latency_ms', 1)

    # Complex bug condition: if base == penalty + latency, divisor is 0
    divisor = base - penalty - latency
    return 1000 / divisor

def process_health_data(data):
    for node in data.get("nodes", []):
        node_id = node.get("id", "unknown")
        metrics = node.get("metrics", {})
        try:
            score = compute_score(metrics)
            print(f"Node {node_id} score: {score}")
        except ZeroDivisionError as e:
            raise ZeroDivisionError(f"Crash processing node {node_id}") from e

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python health_aggregator.py <payload.json>")
        sys.exit(1)

    try:
        with open(sys.argv[1], 'r') as f:
            data = json.load(f)
        process_health_data(data)
    except Exception as e:
        print(f"Fatal Error: {type(e).__name__}: {e}")
        sys.exit(1)
EOF

    cat << 'EOF' > /home/user/logs/aggregator.log
2023-10-25 14:02:11 INFO Starting health aggregation run...
2023-10-25 14:02:11 INFO Processed node web-01 successfully.
2023-10-25 14:02:11 ERROR Fatal Exception encountered!
Traceback (most recent call last):
  File "/home/user/health_aggregator.py", line 22, in process_health_data
    score = compute_score(metrics)
  File "/home/user/health_aggregator.py", line 11, in compute_score
    return 1000 / divisor
ZeroDivisionError: division by zero
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
