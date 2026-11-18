#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_setup.py
import csv
import random

# Generate sys_metrics.csv
random.seed(42)
anomalies = [1685001200, 1685014500, 1685038800]
with open('/home/user/sys_metrics.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'cpu_usage', 'mem_usage', 'execution_duration'])
    start_time = 1685000000
    for i in range(100):
        ts = start_time + i * 600
        cpu = round(random.uniform(5.0, 15.0), 2)
        mem = round(random.uniform(20.0, 30.0), 2)
        if ts in anomalies:
            duration = round(random.uniform(4.5, 5.5), 2)
        else:
            duration = round(random.uniform(0.1, 0.3), 2)
        writer.writerow([ts, cpu, mem, duration])

# Generate suspicious_worker.py
script_content = """import os
import sys
import base64

def check_environment():
    # Misconfiguration check
    if os.environ.get('C2_ROLE') != 'primary_exfil':
        return False
    if os.environ.get('DEBUG') == '1':
        return False
    return True

def decrypt_c2(encoded_payload, key):
    decoded = base64.b64decode(encoded_payload)
    return ''.join(chr(c ^ key) for c in decoded)

def run_worker():
    # Normal operations
    cpu = 12.5
    mem = 25.0

    if check_environment():
        # The key is expected to be an integer derived from state
        # Secret key is 42
        secret_payload = b'T1o/Tzo3ODs+TTo='
        target_ip = decrypt_c2(secret_payload, 42)
        print(f"Connecting to C2: {target_ip}")
    else:
        print("Worker ran successfully.")

if __name__ == '__main__':
    run_worker()
"""
with open('/home/user/suspicious_worker.py', 'w') as f:
    f.write(script_content)
EOF

    python3 /home/user/generate_setup.py
    rm /home/user/generate_setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
