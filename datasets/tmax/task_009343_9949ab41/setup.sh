#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import csv
import os

data = [
    ("2023-10-01T10:00:00Z", "auth-service", "{\n  \"port\": 8080,\n  \"debug\": true\n}"), # len 35
    ("2023-10-01T10:05:00Z", "auth-service", "{\n  \"port\": 8080,\n  \"debug\": true\n}"), # duplicate -> drop
    ("2023-10-01T10:10:00Z", "payment-api", "worker_processes 4;\nlisten 443 ssl;\n"), # len 37
    ("2023-10-01T10:15:00Z", "auth-service", "{\n  \"port\": 8080,\n  \"debug\": false\n}"), # len 36
    ("2023-10-01T10:20:00Z", "payment-api", "worker_processes 4;\nlisten 443 ssl;\n"), # duplicate -> drop
    ("2023-10-01T10:25:00Z", "payment-api", "worker_processes 8;\nlisten 443 ssl;\n"), # len 37
    ("2023-10-01T10:30:00Z", "auth-service", "{\n  \"port\": 8081,\n  \"debug\": false\n}"), # len 36
    ("2023-10-01T10:35:00Z", "auth-service", "{\n  \"port\": 8081,\n  \"debug\": false\n}"), # duplicate -> drop
    ("2023-10-01T10:40:00Z", "auth-service", "{\n  \"port\": 8081,\n  \"debug\": true,\n  \"trace\": 1\n}"), # len 50
    ("2023-10-01T10:45:00Z", "payment-api", "worker_processes 8;\nlisten 8443 ssl;\n"), # len 38
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/config_changes.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "service_name", "config_payload"])
    writer.writerows(data)
EOF
    python3 /tmp/setup_data.py

    chmod -R 777 /home/user
