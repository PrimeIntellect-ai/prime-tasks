#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random
import os

log_path = "/home/user/config_audit.log"
os.makedirs(os.path.dirname(log_path), exist_ok=True)

valid_ips = ["10.0.0.5", "192.168.1.100", "172.16.0.42", "8.8.8.8", "10.10.10.10"]
invalid_ips = ["1.1.1.1", "2.2.2.2", "3.3.3.3"]

records = []
# Generate a few specific valid records
for ip in valid_ips:
    records.append(f"""[RECORD_START]
Timestamp: 1690000000
Service: firewall
Action: ALLOW
TargetIP: {ip}
Details:
Updating firewall rules
Applying new config
Status: success inside details but this is a trap!
Status: SUCCESS
[RECORD_END]""")

# Generate some invalid records
for ip in invalid_ips:
    records.append(f"""[RECORD_START]
Timestamp: 1690000010
Service: firewall
Action: ALLOW
TargetIP: {ip}
Details:
Failed to apply
Status: FAILURE
[RECORD_END]""")

    records.append(f"""[RECORD_START]
Timestamp: 1690000020
Service: webserver
Action: ALLOW
TargetIP: {ip}
Details:
Restarting nginx
Status: SUCCESS
[RECORD_END]""")

# Shuffle and write
random.seed(42)
random.shuffle(records)

with open(log_path, "w") as f:
    f.write("\n".join(records) + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
