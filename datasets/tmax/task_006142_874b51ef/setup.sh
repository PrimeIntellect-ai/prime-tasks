#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_log.py
import gzip
import random
from datetime import datetime, timedelta

random.seed(42)

actions = ["CREATE", "UPDATE", "DELETE"]
keys = ["db_timeout", "max_connections", "cache_size", "retry_limit", "log_level"]
servers = [f"srv-{i:03d}" for i in range(1, 101)]

target_matches = 1234 # We will force exactly this many matches
current_matches = 0

start_time = datetime(2023, 1, 1)

with gzip.open("/home/user/server_configs.log.gz", "wt") as f:
    for i in range(50000):
        timestamp = (start_time + timedelta(minutes=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
        server = random.choice(servers)

        # Determine if this line should be a target match
        if current_matches < target_matches and random.random() < 0.05:
            action = "UPDATE"
            key = "db_timeout"
            current_matches += 1
        else:
            action = random.choice(actions)
            key = random.choice(keys)
            # Ensure we don't accidentally create a target match
            if action == "UPDATE" and key == "db_timeout":
                key = "max_connections"

        value = str(random.randint(10, 5000))

        f.write(f"{timestamp} | {server} | {action} | {key} | {value}\n")

    # If we haven't hit the target, pad the end
    while current_matches < target_matches:
        i += 1
        timestamp = (start_time + timedelta(minutes=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
        server = random.choice(servers)
        f.write(f"{timestamp} | {server} | UPDATE | db_timeout | {random.randint(10, 5000)}\n")
        current_matches += 1
EOF

    python3 /tmp/generate_log.py
    rm /tmp/generate_log.py

    chmod -R 777 /home/user
