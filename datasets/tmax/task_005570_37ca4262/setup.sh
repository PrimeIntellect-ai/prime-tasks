#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import csv
import os

data = [
    # dev environment (servers: dev-a, dev-b, dev-c)
    ("2023-10-01T08:00:00Z", "dev-a", "dev", "debug=true;port=8080"),
    ("2023-10-02T09:00:00Z", "dev-a", "dev", "debug=true;port=8080"), # Duplicate text
    ("2023-10-04T10:00:00Z", "dev-a", "dev", "debug=false;port=8080"),
    ("2023-10-01T12:00:00Z", "dev-b", "dev", "debug=true;port=8081"),
    ("2023-10-05T12:00:00Z", "dev-c", "dev", "debug=true;port=8082"), # Later start

    # prod environment (servers: prod-a, prod-b, prod-c)
    ("2023-09-28T10:00:00Z", "prod-a", "prod", "workers=4;timeout=30"), # Before window
    ("2023-10-03T14:00:00Z", "prod-a", "prod", "workers=8;timeout=30"),
    ("2023-10-03T16:00:00Z", "prod-a", "prod", "workers=8;timeout=60"), # Same day update
    ("2023-10-01T00:00:00Z", "prod-b", "prod", "workers=4;timeout=30"),
    ("2023-10-06T00:00:00Z", "prod-b", "prod", "workers=4;timeout=30"),
    ("2023-10-01T11:00:00Z", "prod-c", "prod", "workers=4;timeout=30"),

    # staging environment (servers: stage-a)
    ("2023-10-02T10:00:00Z", "stage-a", "staging", "cache=redis;ttl=3600"),
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/config_history.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "server_name", "environment", "config_text"])
    writer.writerows(data)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
