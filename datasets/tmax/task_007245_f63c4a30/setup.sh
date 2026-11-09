#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_logs.py
import os
import json
import random
from datetime import datetime, timedelta

log_path = '/home/user/traffic.log'
os.makedirs(os.path.dirname(log_path), exist_ok=True)

start_time = datetime(2023, 10, 10, 12, 0, 0)
attacker_ip = "192.168.45.201"
legit_ips = ["10.0.0.5", "10.0.0.12", "172.16.0.4"]
passwords = ["admin", "123456", "password", "qwerty", "letmein123", "root", "admin123", "P@ssw0rd2023!"]
successful_pass = "P@ssw0rd2023!"

lfi_payloads = [
    "../../../../etc/shadow",
    "../../../windows/win.ini",
    "../../../../var/log/auth.log",
    "../../../../../../../../etc/passwd"
]
successful_lfi = "../../../../../../../../etc/passwd"

random.seed(42)

with open(log_path, 'w') as f:
    current_time = start_time

    # Noise
    for _ in range(20):
        ip = random.choice(legit_ips)
        f.write(f"[{current_time.strftime('%d/%b/%Y:%H:%M:%S +0000')}] {ip} GET /api/health - 200\n")
        current_time += timedelta(seconds=random.randint(5, 30))

    # Brute force
    for p in passwords:
        status = 200 if p == successful_pass else 401
        body = json.dumps({"user": "admin", "pass": p})
        f.write(f"[{current_time.strftime('%d/%b/%Y:%H:%M:%S +0000')}] {attacker_ip} POST /api/login {body} {status}\n")
        current_time += timedelta(seconds=2)

        # Interleave some noise
        if random.random() > 0.5:
            ip = random.choice(legit_ips)
            f.write(f"[{current_time.strftime('%d/%b/%Y:%H:%M:%S +0000')}] {ip} GET /api/data?file=logo.png - 200\n")

    current_time += timedelta(minutes=1)

    # LFI Scan
    for payload in lfi_payloads:
        status = 200 if payload == successful_lfi else 404
        f.write(f"[{current_time.strftime('%d/%b/%Y:%H:%M:%S +0000')}] {attacker_ip} GET /api/data?file={payload} - {status}\n")
        current_time += timedelta(seconds=1)

    # More noise
    for _ in range(10):
        ip = random.choice(legit_ips)
        f.write(f"[{current_time.strftime('%d/%b/%Y:%H:%M:%S +0000')}] {ip} GET /api/health - 200\n")
        current_time += timedelta(seconds=random.randint(5, 30))
EOF

    python3 /tmp/setup_logs.py
    rm /tmp/setup_logs.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
