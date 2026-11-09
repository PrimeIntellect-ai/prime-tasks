#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the script to generate the logs
    cat << 'EOF' > /home/user/generate_logs.py
#!/usr/bin/env python3
import json
import uuid
import random

def generate_logs():
    logs = []

    # Noise logs
    for _ in range(500):
        logs.append({
            "timestamp": f"2023-10-01T10:{random.randint(10, 59):02d}:{random.randint(0, 59):02d}Z",
            "ip_address": f"192.168.1.{random.randint(1, 250)}",
            "endpoint": random.choice(["/home", "/about", "/login", "/api/data"]),
            "status_code": random.choice([200, 404, 500, 401]),
            "request_id": str(uuid.uuid4()),
            "payload_hash": str(uuid.uuid4()).replace('-', '')
        })

    # Suspicious Event 1: 10.0.0.5 in bucket 10:00:00, 6 unique payloads (401s)
    for i in range(6):
        logs.append({
            "timestamp": f"2023-10-01T10:02:0{i}Z",
            "ip_address": "10.0.0.5",
            "endpoint": "/login",
            "status_code": 401,
            "request_id": str(uuid.uuid4()),
            "payload_hash": f"hash_a_{i}"
        })

    # Suspicious Event 2: 172.16.0.8 in bucket 10:00:00, 7 unique payloads
    for i in range(7):
        logs.append({
            "timestamp": f"2023-10-01T10:04:1{i}Z",
            "ip_address": "172.16.0.8",
            "endpoint": "/login",
            "status_code": 401,
            "request_id": str(uuid.uuid4()),
            "payload_hash": f"hash_b_{i}"
        })

    # False Positive 1: 192.168.1.1 makes 10 requests, but same payload hash (Count = 1)
    for i in range(10):
        logs.append({
            "timestamp": f"2023-10-01T10:03:1{i}Z",
            "ip_address": "192.168.1.1",
            "endpoint": "/login",
            "status_code": 401,
            "request_id": str(uuid.uuid4()),
            "payload_hash": "same_hash_every_time"
        })

    # False Positive 2: 10.0.0.9 makes 6 unique requests, but split across two buckets (10:04 and 10:06)
    for i in range(3):
        logs.append({
            "timestamp": f"2023-10-01T10:04:5{i}Z",
            "ip_address": "10.0.0.9",
            "endpoint": "/login",
            "status_code": 401,
            "request_id": str(uuid.uuid4()),
            "payload_hash": f"hash_c_{i}"
        })
    for i in range(3):
        logs.append({
            "timestamp": f"2023-10-01T10:06:0{i}Z", # Next bucket
            "ip_address": "10.0.0.9",
            "endpoint": "/login",
            "status_code": 401,
            "request_id": str(uuid.uuid4()),
            "payload_hash": f"hash_d_{i}"
        })

    # False Positive 3: 10.0.0.10 has 6 requests, but 2 share the same request_id (duplicates). Real count = 4.
    req_ids = [str(uuid.uuid4()) for _ in range(4)]
    payloads = [f"hash_e_{i}" for i in range(4)]

    for i in range(4):
        logs.append({
            "timestamp": f"2023-10-01T10:08:1{i}Z", # Bucket 10:05:00
            "ip_address": "10.0.0.10",
            "endpoint": "/login",
            "status_code": 401,
            "request_id": req_ids[i],
            "payload_hash": payloads[i]
        })
    # Add duplicates of the first two
    for i in range(2):
        logs.append({
            "timestamp": f"2023-10-01T10:08:2{i}Z", 
            "ip_address": "10.0.0.10",
            "endpoint": "/login",
            "status_code": 401,
            "request_id": req_ids[i], # Duplicate!
            "payload_hash": payloads[i]
        })

    random.seed(42)
    random.shuffle(logs)

    with open("/home/user/raw_access_logs.jsonl", "w") as f:
        for log in logs:
            f.write(json.dumps(log) + "\n")

if __name__ == "__main__":
    generate_logs()
EOF

    # Run the generation script and remove it
    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    # Create the expected output file
    cat << 'EOF' > /home/user/expected_suspicious_activity.json
[
  {
    "time_bucket": "2023-10-01T10:00:00Z",
    "ip_address": "10.0.0.5",
    "unique_payloads": 6
  },
  {
    "time_bucket": "2023-10-01T10:00:00Z",
    "ip_address": "172.16.0.8",
    "unique_payloads": 7
  }
]
EOF

    chmod -R 777 /home/user
