#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_logs.py
import random
import datetime

random.seed(42)

servers = ["srv-web-01", "srv-web-02", "srv-web-03", "srv-db-01", "srv-cache-01"]
start_date = datetime.datetime(2024, 1, 1, 0, 0, 0)

with open("/home/user/config_stream.log", "w") as f:
    current_time = start_date
    for i in range(50000):
        current_time += datetime.timedelta(minutes=random.randint(1, 10))
        if current_time.month > 2:
            break

        server = random.choice(servers)

        # Add noise lines
        if random.random() < 0.8:
            f.write(f"[{current_time.strftime('%Y-%m-%d %H:%M:%S')}] [{server}] [INFO] system: health check passed\n")
            continue

        # Target lines
        mc = random.choice([100, 150, 200, 350, 500, 800])
        to = random.choice(["30s", "60s", "1m", "2m", "120s"])

        # Hardcode some specific anomalies for the target servers to ensure testability
        if current_time.date() == datetime.date(2024, 1, 5) and server == "srv-web-01":
            mc = 250
            to = "1m"
        if current_time.date() == datetime.date(2024, 1, 12) and server == "srv-web-02":
            mc = 400
            to = "120s"
        if current_time.date() == datetime.date(2024, 1, 20) and server == "srv-web-03":
            mc = 1000
            to = "2m"

        f.write(f"[{current_time.strftime('%Y-%m-%d %H:%M:%S')}] [{server}] [INFO] deploy_bot: \"Updated config. max_connections={mc}, timeout={to}\"\n")
EOF
    python3 /home/user/generate_logs.py
    rm /home/user/generate_logs.py

    chmod -R 777 /home/user
