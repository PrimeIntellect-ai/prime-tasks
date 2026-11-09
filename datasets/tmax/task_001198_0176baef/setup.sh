#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_logs.py
import random
from datetime import datetime, timedelta

def generate_logs():
    random.seed(42)
    ips = [f"10.0.0.{i}" for i in range(1, 6)]
    methods = ["GET", "POST", "PUT"]
    urls = ["/home", "/api/v1/users", "/login", "/api/v1/data"]

    start_time = datetime(2024, 3, 15, 10, 0, 0)

    with open("/home/user/server_logs.log", "w") as f:
        for i in range(1, 15001):
            timestamp = (start_time + timedelta(seconds=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
            ip = random.choice(ips)
            method = random.choice(methods)
            url = random.choice(urls)

            # Status code logic
            status = 200
            if random.random() < 0.05:
                status = random.choice([400, 401, 403, 404, 500, 502, 503])

            # Response time logic (introduce an anomaly block between 5000 and 6000)
            if 5000 <= i <= 6000:
                resp_time = random.randint(1000, 2000)
            else:
                resp_time = random.randint(50, 300)

            f.write(f"{timestamp} {ip} {method} {url} {status} {resp_time}\n")

if __name__ == "__main__":
    generate_logs()
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
