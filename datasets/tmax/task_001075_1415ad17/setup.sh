#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import random
import datetime

random.seed(42)

def generate_logs(filepath):
    ips_normal = [f"192.168.1.{i}" for i in range(10, 50)]
    attacker_ip_1 = "10.0.0.55"  # 401s
    attacker_ip_2 = "172.16.0.101" # 500s
    attacker_ip_3 = "10.0.0.99" # 404s

    endpoints = ["/index.html", "/login", "/api/data", "/images/logo.png"]
    methods = ["GET", "POST"]

    with open(filepath, "w") as f:
        for i in range(20000):
            # Normal traffic
            ip = random.choice(ips_normal)
            method = random.choice(methods)
            endpoint = random.choice(endpoints)
            status = 200
            size = random.randint(100, 5000)

            # Inject attackers
            if i % 50 == 0:
                ip = attacker_ip_1
                method = "POST"
                endpoint = "/login"
                status = 401
            elif i % 150 == 0:
                ip = attacker_ip_2
                method = "GET"
                endpoint = "/api/data"
                status = 500
            elif i % 300 == 0:
                ip = attacker_ip_3
                method = "GET"
                endpoint = "/hidden_admin"
                status = 404

            timestamp = (datetime.datetime(2023, 1, 1) + datetime.timedelta(seconds=i*5)).strftime("%d/%b/%Y:%H:%M:%S +0000")

            log_line = f'{ip} - - [{timestamp}] "{method} {endpoint} HTTP/1.1" {status} {size}\n'
            f.write(log_line)

generate_logs("/home/user/access.log")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
