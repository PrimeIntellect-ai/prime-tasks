#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    mkdir -p /app/configs

    # Create a valid 1x1 PNG file for policy_memo.png
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" | base64 -d > /app/policy_memo.png

    cat << 'EOF' > /tmp/setup_env.py
import os
import random
import json
from datetime import datetime, timedelta

os.makedirs('/app/configs', exist_ok=True)
ground_truth = {"blocked_ips": [], "non_compliant_files": []}

# Generate Logs
log_entries = []
start_time = datetime(2023, 1, 1, 12, 0, 0)
ips = [f"192.168.1.{i}" for i in range(1, 101)]

# Normal traffic
for _ in range(1000):
    t = start_time + timedelta(seconds=random.randint(0, 86400))
    log_entries.append((t, random.choice(ips), "SUCCESS"))

# Malicious traffic (Violates policy: > 5 consecutive failures in 10 mins -> 6 failures)
malicious_ips = ["10.0.0.7", "192.168.1.42", "192.168.1.99"]
ground_truth["blocked_ips"] = sorted(malicious_ips)

for ip in malicious_ips:
    t = start_time + timedelta(seconds=random.randint(0, 80000))
    for i in range(6): # 6 consecutive failures
        log_entries.append((t + timedelta(minutes=i), ip, "FAILED"))

# Sort logs and write
log_entries.sort()
with open('/app/auth.log', 'w') as f:
    for entry in log_entries:
        f.write(f"{entry[0].strftime('%Y-%m-%dT%H:%M:%S')} {entry[1]} {entry[2]}\n")

# Generate Config Files
valid_token = "sk_live_1234567890abcdef1234567890abcdef"
invalid_token = "sk_test_1234567890abcdef1234567890abcdef"

for i in range(20):
    filepath = f"/app/configs/config_{i}.conf"
    is_bad_perms = i % 3 == 0
    is_bad_token = i % 4 == 0

    with open(filepath, 'w') as f:
        if is_bad_token:
            f.write(f"api_token={invalid_token}\n")
        else:
            f.write(f"api_token={valid_token}\n")

    if is_bad_perms:
        os.chmod(filepath, 0o644)
    else:
        os.chmod(filepath, 0o600)

    if is_bad_perms or is_bad_token:
        ground_truth["non_compliant_files"].append(filepath)

ground_truth["non_compliant_files"].sort()

with open('/app/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)
EOF

    python3 /tmp/setup_env.py
    rm /tmp/setup_env.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
