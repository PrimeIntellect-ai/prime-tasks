#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import csv
import random
import os

os.makedirs('/home/user', exist_ok=True)

random.seed(42)

status_codes = [200, 404, 500, 503]
web_errors = [
    "Connection timeout to upstream",
    "Null pointer exception in handler",
    "Invalid input syntax",
    "User not authorized for resource",
    "Missing parameters in request",
    "Unexpected EOF while parsing"
]

db_errors = [
    "Connection timeout to upstream db",
    "Null pointer exception in db_handler",
    "Invalid syntax in query",
    "Role not authorized for table",
    "Missing fields in payload",
    "Unexpected EOF in stream"
]

web_data = []
db_data = []

for i in range(1000):
    req_id = f"REQ-{i:04d}"
    status = random.choice(status_codes)
    ip = f"{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}.{random.randint(1,255)}"
    err_idx = random.randint(0, len(web_errors)-1)
    web_err = web_errors[err_idx]

    web_data.append({
        "timestamp": f"2023-10-01T10:{i%60:02d}:00Z",
        "ip_address": ip,
        "status_code": status,
        "endpoint": "/api/v1/resource",
        "error_msg": web_err,
        "req_id": req_id
    })

    # 30% chance to have a matching db log
    if random.random() < 0.3:
        email = f"user{i}@company.com"
        # Sometimes introduce an exact match, sometimes minor mutation
        db_err = db_errors[err_idx]

        db_data.append({
            "timestamp": f"2023-10-01T10:{i%60:02d}:05Z",
            "user_email": email,
            "db_error": db_err,
            "req_id": req_id
        })

        # Sometimes insert a noise db log with same req_id
        if random.random() < 0.5:
            db_data.append({
                "timestamp": f"2023-10-01T10:{i%60:02d}:06Z",
                "user_email": email,
                "db_error": "Some completely unrelated database error that has high edit distance",
                "req_id": req_id
            })

with open('/home/user/web_logs.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["timestamp", "ip_address", "status_code", "endpoint", "error_msg", "req_id"])
    writer.writeheader()
    writer.writerows(web_data)

with open('/home/user/db_logs.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=["timestamp", "user_email", "db_error", "req_id"])
    writer.writeheader()
    writer.writerows(db_data)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
